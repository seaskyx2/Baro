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

        let currentVersion = BaroBuildInfo.currentVersion

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

                let remote = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n"))
                let htmlURL = Self.sanitizedReleaseURL(json["html_url"] as? String)

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

    private nonisolated static let fallbackReleasesURL = URL(string: "https://github.com/seaskyx2/Baro/releases/latest")!

    /// 严格白名单校验发布跳转链接：仅放行官方仓库的 HTTPS GitHub URL，阻断 `file://` / `smb://` 或自定义协议注入
    nonisolated public static func sanitizedReleaseURL(_ rawURLString: String?) -> URL {
        guard let raw = rawURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com",
              url.path.hasPrefix("/seaskyx2/Baro/") else {
            return fallbackReleasesURL
        }
        return url
    }

    nonisolated public static func isVersionNewer(remote: String, current: String) -> Bool {
        guard let rSemVer = parseSemVer(remote),
              let cSemVer = parseSemVer(current) else {
            return false
        }

        let count = max(rSemVer.core.count, cSemVer.core.count)
        for i in 0..<count {
            let r = i < rSemVer.core.count ? rSemVer.core[i] : 0
            let c = i < cSemVer.core.count ? cSemVer.core[i] : 0
            if r != c { return r > c }
        }

        // 核心数字完全相等时按 SemVer 2.0 比较预发布后缀：正式版 > 同版本号的预发布版（如 1.4.1 > 1.4.1-rc.2）
        switch (rSemVer.prerelease, cSemVer.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case let (.some(rPre), .some(cPre)):
            let rTokens = rPre.split(separator: ".").map(String.init)
            let cTokens = cPre.split(separator: ".").map(String.init)
            let minLen = min(rTokens.count, cTokens.count)
            for idx in 0..<minLen {
                let rt = rTokens[idx]
                let ct = cTokens[idx]
                if rt == ct { continue }
                if let rn = Int(rt), let cn = Int(ct) {
                    return rn > cn
                }
                if Int(rt) != nil { return false } // SemVer: 纯数字预发布段优先级低于含字母段
                if Int(ct) != nil { return true }
                return rt > ct
            }
            return rTokens.count > cTokens.count
        }
    }

    private nonisolated static func parseSemVer(_ raw: String) -> (core: [Int], prerelease: String?)? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n"))
        guard !trimmed.isEmpty else { return nil }

        let withoutBuild = String(trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let dashSplit = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreStr = String(dashSplit[0])
        guard !coreStr.isEmpty else { return nil }

        let rawNums = coreStr.split(separator: ".", omittingEmptySubsequences: false)
        var nums: [Int] = []
        nums.reserveCapacity(rawNums.count)
        for seg in rawNums {
            guard let n = Int(seg), n >= 0 else { return nil }
            nums.append(n)
        }

        let pre: String?
        if dashSplit.count > 1 {
            let p = String(dashSplit[1])
            guard !p.isEmpty else { return nil }
            pre = p
        } else {
            pre = nil
        }
        return (nums, pre)
    }
}
