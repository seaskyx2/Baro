import Foundation

public enum BaroBuildInfo {
    public static let fallbackVersion = "1.3.1"

    public static var currentVersion: String {
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !ver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ver
        }
        return fallbackVersion
    }
}
