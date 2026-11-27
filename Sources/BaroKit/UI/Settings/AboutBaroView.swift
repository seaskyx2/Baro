import AppKit
import BaroCore
import SwiftUI

public struct AboutBaroView: View {
    @ObservedObject public var settings: BaroSettings
    @StateObject private var updateChecker = UpdateChecker()

    public init(settings: BaroSettings) {
        self.settings = settings
    }

    public var body: some View {
        let lang = settings.resolvedLanguage
        let version = BaroBuildInfo.currentVersion

        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }

            VStack(spacing: 4) {
                Text(BaroL10n.t("Baro 晴雨表", "Baro", lang: lang))
                    .font(.system(size: 19, weight: .bold))
                Text("v\(version) · Apple Silicon Native")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(BaroL10n.t(
                "纯只读、零入侵的 macOS 系统状态晴雨表",
                "Read-only vitals for macOS. Zero intrusion.",
                lang: lang
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                promiseRow(icon: "eye", text: BaroL10n.t("绝对只读：无清理、无强杀进程、无硬件改写", "Read-Only: no cleaner, no kill switch, no hardware writes", lang: lang))
                promiseRow(icon: "lock.shield", text: BaroL10n.t("零隐私弹窗：不申请定位与蓝牙，默认不联网", "Zero Prompts: no Location/Bluetooth, offline by default", lang: lang))
                promiseRow(icon: "bolt.batteryblock", text: BaroL10n.t("极简轻巧：原生模板图自绘，息屏自动休眠", "Ultra-Light: native template rendering, sleep-aware", lang: lang))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            updateStatusView(lang: lang)

            HStack(spacing: 8) {
                Button(BaroL10n.t("检查更新", "Check Updates", lang: lang)) {
                    updateChecker.checkManually(lang: lang)
                }
                .buttonStyle(.bordered)
                .disabled(updateChecker.state == .checking)

                Button(BaroL10n.t("使用指南", "User Guide", lang: lang)) {
                    let urlString = lang == .zhHans
                        ? "https://github.com/seaskyx2/Baro/blob/main/docs/USER_GUIDE.md"
                        : "https://github.com/seaskyx2/Baro/blob/main/docs/USER_GUIDE.en.md"
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button(BaroL10n.t("GitHub", "GitHub", lang: lang)) {
                    if let url = URL(string: "https://github.com/seaskyx2/Baro") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    @ViewBuilder
    private func updateStatusView(lang: ResolvedLanguage) -> some View {
        switch updateChecker.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(BaroL10n.t("正在检查 GitHub Releases…", "Checking GitHub Releases…", lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .upToDate(let current):
            Text(BaroL10n.t("当前 v\(current) 已是最新版本", "v\(current) is up to date", lang: lang))
                .font(.caption)
                .foregroundStyle(BaroPalette.batteryHealthy)
        case .updateAvailable(let latest, let url):
            HStack(spacing: 6) {
                Text(BaroL10n.t("发现新版本 \(latest)", "New release \(latest) available", lang: lang))
                    .font(.caption)
                    .foregroundStyle(BaroPalette.power)
                Button(BaroL10n.t("前往下载", "Download", lang: lang)) {
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
                .buttonStyle(.link)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func promiseRow(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.88))
        }
    }
}
