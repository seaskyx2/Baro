import BaroCore
import Foundation

public enum UpdateCheckState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(current: String)
    case updateAvailable(latest: String, url: URL)
    case failed(message: String)
}

@MainActor
public final class UpdateChecker: ObservableObject {
    @Published public private(set) var state: UpdateCheckState = .idle

    public init() {}

    /// 严格离线原则：仅在用户主动点击按钮时请求一次 GitHub Releases API
    public func checkManually(lang: ResolvedLanguage) {
        guard state != .checking else { return }
        state = .checking

        let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.2.0"

        Task {
            do {
                guard let apiURL = URL(string: "https://api.github.com/repos/seaskyx2/Baro/releases/latest") else {
                    self.state = .failed(message: BaroL10n.t("无效的更新地址", "Invalid URL", lang: lang))
                    return
                }
                var req = URLRequest(url: apiURL)
                req.timeoutInterval = 8
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("Baro/\(currentVersion)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    self.state = .failed(message: BaroL10n.t("暂时无法连接 GitHub", "Unable to reach GitHub", lang: lang))
                    return
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.state = .failed(message: BaroL10n.t("解析版本信息失败", "Invalid release payload", lang: lang))
                    return
                }

                let remote = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))
                    ?? URL(string: "https://github.com/seaskyx2/Baro/releases/latest")!

                if Self.isVersionNewer(remote: remote, current: currentVersion) {
                    self.state = .updateAvailable(latest: tagName, url: htmlURL)
                } else {
                    self.state = .upToDate(current: currentVersion)
                }
            } catch {
                self.state = .failed(message: BaroL10n.t("检查失败，请稍后重试", "Check failed, try again later", lang: lang))
            }
        }
    }

    public static func isVersionNewer(remote: String, current: String) -> Bool {
        let rParts = remote.split(separator: ".").compactMap { Int($0) }
        let cParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(rParts.count, cParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if r != c { return r > c }
        }
        return false
    }
}
