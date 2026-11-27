import SwiftUI

public struct CircularGaugeView: View {
    public let progress: Double
    public let tint: Color
    public let lineWidth: CGFloat
    public let centerLabel: String

    public init(
        progress: Double,
        tint: Color,
        lineWidth: CGFloat = 4.5,
        centerLabel: String
    ) {
        self.progress = min(1.0, max(0.0, progress))
        self.tint = tint
        self.lineWidth = lineWidth
        self.centerLabel = centerLabel
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)

            Text(centerLabel)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}
