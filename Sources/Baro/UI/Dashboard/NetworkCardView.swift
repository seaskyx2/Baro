import BaroCore
import SwiftUI

public struct NetworkCardView: View {
    public let network: NetworkSnapshot
    public let downloadHistory: [Double]
    public let uploadHistory: [Double]
    public let lang: ResolvedLanguage

    public init(
        network: NetworkSnapshot,
        downloadHistory: [Double],
        uploadHistory: [Double],
        lang: ResolvedLanguage
    ) {
        self.network = network
        self.downloadHistory = downloadHistory
        self.uploadHistory = uploadHistory
        self.lang = lang
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(BaroL10n.t("网络吞吐", "Network", lang: lang), systemImage: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(network.primaryInterface)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            VStack(spacing: 4) {
                speedLine(
                    arrow: "↓",
                    speed: ByteFormatter.detailedRate(network.downloadBytesPerSec),
                    color: BaroPalette.download,
                    history: downloadHistory
                )
                speedLine(
                    arrow: "↑",
                    speed: ByteFormatter.detailedRate(network.uploadBytesPerSec),
                    color: BaroPalette.upload,
                    history: uploadHistory
                )
            }

            Spacer(minLength: 0)

            HStack {
                Text(network.localIPAddress)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(BaroL10n.t("累计 ", "Total ", lang: lang) + ByteFormatter.diskSize(network.sessionDownloadBytes + network.sessionUploadBytes))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .bentoCard()
    }

    private func speedLine(arrow: String, speed: String, color: Color, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(arrow)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(speed)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                Spacer()
            }
            SparklineView(
                values: history,
                lineColor: color,
                fixedMax: nil,
                valueFormatter: { ByteFormatter.compactRate($0) }
            )
            .frame(height: 16)
        }
    }
}
