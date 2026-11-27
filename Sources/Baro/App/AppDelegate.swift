import AppKit
import BaroCore
import Combine
import SwiftUI

final class BaroFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = BaroSettings()
    private lazy var coordinator = SamplingCoordinator(settings: settings)

    private var statusItem: NSStatusItem!
    private var statusHostingView: NSHostingView<MenuBarContentView>!
    private var dashboardPanel: BaroFloatingPanel?
    private var dashboardHostingController: NSHostingController<DashboardPopoverView>?
    private var settingsWindow: NSWindow?

    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        coordinator.start()

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItemWidth()
            }
            .store(in: &cancellables)

        coordinator.$healthSummary
            .map(\.level)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItemWidth()
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshStatusItemWidth()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        removeMonitors()
    }

    // MARK: - Single NSStatusItem

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menuView = MenuBarContentView(coordinator: coordinator, settings: settings)
        statusHostingView = NSHostingView(rootView: menuView)
        statusHostingView.frame = NSRect(x: 0, y: 0, width: 108, height: 22)

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.addSubview(statusHostingView)
            refreshStatusItemWidth()
        }
    }

    private func refreshStatusItemWidth() {
        guard let button = statusItem.button, let hosting = statusHostingView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let targetWidth = max(32, ceil(fitting.width) + 4)
        let targetHeight = max(22, button.bounds.height)
        if abs(targetWidth - statusItem.length) >= 2 || statusItem.length <= 0 {
            hosting.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            button.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            statusItem.length = targetWidth
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        toggleDashboardPanel()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开晴雨表仪表盘", action: #selector(openDashboardFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Baro", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDashboardFromMenu() {
        if dashboardPanel?.isVisible != true {
            toggleDashboardPanel()
        }
    }

    @objc private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Floating Liquid Glass Panel

    private func toggleDashboardPanel() {
        if let panel = dashboardPanel, panel.isVisible {
            closeDashboardPanel()
        } else {
            showDashboardPanel()
        }
    }

    private func ensureDashboardPanel() -> BaroFloatingPanel {
        if let existing = dashboardPanel {
            return existing
        }

        let rootView = DashboardPopoverView(
            coordinator: coordinator,
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.closeDashboardPanel()
                self?.openSettingsWindow()
            },
            onLayoutChanged: { [weak self] in
                DispatchQueue.main.async {
                    self?.resizePanelKeepingTopAnchor()
                }
            }
        )

        let hosting = NSHostingController(rootView: rootView)
        let fitting = hosting.view.fittingSize

        let panel = BaroFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 364, height: max(320, fitting.height)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = hosting
        panel.delegate = self

        self.dashboardHostingController = hosting
        self.dashboardPanel = panel
        return panel
    }

    private func showDashboardPanel() {
        let panel = ensureDashboardPanel()
        coordinator.setPanelOpen(true)

        positionPanelBelowStatusItem(panel)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.resizePanelKeepingTopAnchor()
        }
        installDismissMonitors()
    }

    private func closeDashboardPanel() {
        dashboardPanel?.orderOut(nil)
        coordinator.setPanelOpen(false)
        removeMonitors()
    }

    private func positionPanelBelowStatusItem(_ panel: NSPanel) {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonFrameInWindow)
        let targetScreen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first

        let fittingSize = dashboardHostingController?.view.fittingSize ?? NSScreen.main?.frame.size ?? CGSize(width: 364, height: 480)
        let width: CGFloat = 364
        let height: CGFloat = max(240, ceil(fittingSize.height))

        var x = buttonScreenRect.midX - width / 2.0
        if let visible = targetScreen?.visibleFrame {
            x = min(x, visible.maxX - width - 8)
            x = max(x, visible.minX + 8)
        }
        let y = buttonScreenRect.minY - height - 6

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func resizePanelKeepingTopAnchor() {
        guard let panel = dashboardPanel, panel.isVisible,
              let hosting = dashboardHostingController else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let newHeight = max(240, ceil(hosting.view.fittingSize.height))
        var frame = panel.frame
        let topY = frame.maxY
        frame.size.height = newHeight
        frame.origin.y = topY - newHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    public func windowDidResignKey(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win === dashboardPanel {
            closeDashboardPanel()
        }
    }

    private func installDismissMonitors() {
        removeMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeDashboardPanel()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closeDashboardPanel()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let global = globalClickMonitor {
            NSEvent.removeMonitor(global)
            globalClickMonitor = nil
        }
        if let local = localKeyMonitor {
            NSEvent.removeMonitor(local)
            localKeyMonitor = nil
        }
    }

    // MARK: - Settings Window

    private func openSettingsWindow() {
        if let existing = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Baro 偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
