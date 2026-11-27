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
    private static let activateNotificationName = Notification.Name("com.baro.monitor.activateDashboard")

    private let settings = BaroSettings()
    private lazy var coordinator = SamplingCoordinator(settings: settings)
    private let hotKeyManager = GlobalHotKeyManager()

    private var statusItem: NSStatusItem!
    private var lastMenuBarSignature: String = ""
    private var dashboardPanel: BaroFloatingPanel?
    private var dashboardHostingController: NSHostingController<DashboardPopoverView>?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    private var idleReleaseTimer: Timer?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var distributedObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfDuplicateInstance() {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        observeAppearanceAndInstanceActivation()
        applyGlobalHotKeySetting()

        coordinator.onMenuBarUpdate = { [weak self] data in
            self?.updateStatusCanvas(with: data)
        }
        coordinator.start()

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.lastMenuBarSignature = ""
                self.updateStatusCanvas(with: self.coordinator.currentMenuBarRenderData())
                self.applyGlobalHotKeySetting()
            }
            .store(in: &cancellables)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        idleReleaseTimer?.invalidate()
        hotKeyManager.unregister()
        removeMonitors()
        for obs in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        distributedObservers.removeAll()
        appearanceObservation?.invalidate()
    }

    // MARK: - Single-Instance Guard

    private func terminateIfDuplicateInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let hasOther = running.contains { $0.processIdentifier != currentPID && !$0.isTerminated }
        if hasOther {
            DistributedNotificationCenter.default().postNotificationName(
                Self.activateNotificationName,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return true
        }
        return false
    }

    private func observeAppearanceAndInstanceActivation() {
        let center = DistributedNotificationCenter.default()

        let themeObs = center.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.forceRedrawMenuBar()
            }
        }
        distributedObservers.append(themeObs)

        let activateObs = center.addObserver(
            forName: Self.activateNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openDashboardFromMenu()
            }
        }
        distributedObservers.append(activateObs)

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.forceRedrawMenuBar()
            }
        }
    }

    private func applyGlobalHotKeySetting() {
        hotKeyManager.configure(
            enabled: settings.enableGlobalHotKey,
            preset: settings.globalHotKeyPreset
        ) { [weak self] in
            self?.toggleDashboardPanel()
        }
    }

    private func forceRedrawMenuBar() {
        lastMenuBarSignature = ""
        updateStatusCanvas(with: coordinator.currentMenuBarRenderData())
    }

    // MARK: - Native Template Image NSStatusItem

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusCanvas(with: coordinator.currentMenuBarRenderData())
        }
    }

    private func updateStatusCanvas(with data: MenuBarRenderData) {
        guard let button = statusItem.button else { return }
        let appearance = button.effectiveAppearance
        let sig = MenuBarImageRenderer.renderSignature(data: data, settings: settings, appearance: appearance)
        guard sig != lastMenuBarSignature else { return }
        lastMenuBarSignature = sig

        let image = MenuBarImageRenderer.render(data: data, settings: settings, appearance: appearance)
        button.image = image
        if abs(image.size.width - statusItem.length) >= 0.5 {
            statusItem.length = image.size.width
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
        let lang = settings.resolvedLanguage
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: BaroL10n.t("打开晴雨表仪表盘", "Open Baro Dashboard", lang: lang),
            action: #selector(openDashboardFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let copyItem = NSMenuItem(
            title: BaroL10n.t("复制系统快照", "Copy System Snapshot", lang: lang),
            action: #selector(copySnapshotFromMenu),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)

        let settingsItem = NSMenuItem(
            title: BaroL10n.t("偏好设置…", "Preferences…", lang: lang),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let styleParent = NSMenuItem(
            title: BaroL10n.t("菜单栏模式", "Menu Bar Style", lang: lang),
            action: nil,
            keyEquivalent: ""
        )
        let styleSubmenu = NSMenu()
        for style in MenuBarStyle.allCases {
            let item = NSMenuItem(
                title: BaroL10n.menuBarStyleTitle(style, lang: lang),
                action: #selector(selectMenuBarStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            item.state = settings.menuBarStyle == style ? .on : .off
            styleSubmenu.addItem(item)
        }
        styleParent.submenu = styleSubmenu
        menu.addItem(styleParent)

        let iconToggleItem = NSMenuItem(
            title: BaroL10n.t("显示晴雨表图标", "Show Barometer Icon", lang: lang),
            action: #selector(toggleMenuBarIconFromMenu),
            keyEquivalent: ""
        )
        iconToggleItem.target = self
        iconToggleItem.state = settings.showMenuBarIcon ? .on : .off
        menu.addItem(iconToggleItem)

        menu.addItem(.separator())

        let guideItem = NSMenuItem(
            title: BaroL10n.t("使用指南", "User Guide", lang: lang),
            action: #selector(openUserGuideFromMenu),
            keyEquivalent: ""
        )
        guideItem.target = self
        menu.addItem(guideItem)

        let aboutItem = NSMenuItem(
            title: BaroL10n.t("关于 Baro", "About Baro", lang: lang),
            action: #selector(openAboutFromMenu),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: BaroL10n.t("退出 Baro", "Quit Baro", lang: lang),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
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

    @objc private func copySnapshotFromMenu() {
        let lang = settings.resolvedLanguage
        let hostInfo = coordinator.hostInfo
        coordinator.captureFreshSnapshot { snap, health in
            let text = SnapshotExporter.formatPlainText(hostInfo: hostInfo, snapshot: snap, health: health, lang: lang)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    @objc private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc private func selectMenuBarStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let chosen = MenuBarStyle(rawValue: raw) else { return }
        settings.menuBarStyle = chosen
        forceRedrawMenuBar()
    }

    @objc private func toggleMenuBarIconFromMenu() {
        settings.showMenuBarIcon.toggle()
        forceRedrawMenuBar()
    }

    @objc private func openUserGuideFromMenu() {
        let lang = settings.resolvedLanguage
        let urlStr = lang == .zhHans
            ? "https://github.com/seaskyx2/Baro/blob/main/docs/USER_GUIDE.md"
            : "https://github.com/seaskyx2/Baro/blob/main/docs/USER_GUIDE.en.md"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAboutFromMenu() {
        openAboutWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Floating Liquid Glass Panel + Idle Memory Release

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
        idleReleaseTimer?.invalidate()
        idleReleaseTimer = nil

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
        scheduleIdlePanelRelease()
    }

    private func scheduleIdlePanelRelease() {
        idleReleaseTimer?.invalidate()
        let timer = Timer(timeInterval: 20.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.dashboardPanel?.isVisible != true else { return }
                self.dashboardPanel?.contentViewController = nil
                self.dashboardPanel?.delegate = nil
                self.dashboardPanel = nil
                self.dashboardHostingController = nil
            }
        }
        timer.tolerance = 5.0
        RunLoop.main.add(timer, forMode: .common)
        idleReleaseTimer = timer
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

    public func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if win === settingsWindow {
            settingsWindow = nil
        } else if win === aboutWindow {
            aboutWindow = nil
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
            if event.keyCode == 53 {
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

    // MARK: - Settings & About Windows

    private func openSettingsWindow() {
        if let existing = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let lang = settings.resolvedLanguage
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = BaroL10n.t("Baro 偏好设置", "Baro Preferences", lang: lang)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = true
        window.delegate = self
        window.center()

        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func openAboutWindow() {
        if let existing = aboutWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let lang = settings.resolvedLanguage
        let hosting = NSHostingController(rootView: AboutBaroView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = BaroL10n.t("关于 Baro", "About Baro", lang: lang)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = true
        window.delegate = self
        window.center()

        self.aboutWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
