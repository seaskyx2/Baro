import SwiftUI

/// 支持鼠标悬停读取游标（Hover Inspect）的平滑折线微图表
public struct SparklineView: View {
    public let values: [Double]
    public let lineColor: Color
    public let fixedMax: Double?
    public let valueFormatter: ((Double) -> String)?

    @State private var hoverLocationX: CGFloat?

    public init(
        values: [Double],
        lineColor: Color,
        fixedMax: Double? = nil,
        valueFormatter: ((Double) -> String)? = nil
    ) {
        self.values = values
        self.lineColor = lineColor
        self.fixedMax = fixedMax
        self.valueFormatter = valueFormatter
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let samples = normalizedSamples
            let hoverIndex = computeHoverIndex(width: size.width, count: samples.count)

            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    guard samples.count >= 2 else { return }

                    let maxVal = max(fixedMax ?? (samples.max() ?? 1.0), 0.0001)
                    let minVal = fixedMax != nil ? 0.0 : min(0.0, samples.min() ?? 0.0)
                    let range = max(maxVal - minVal, 0.0001)

                    var points: [CGPoint] = []
                    points.reserveCapacity(samples.count)
                    let stepX = canvasSize.width / CGFloat(samples.count - 1)

                    for (index, val) in samples.enumerated() {
                        let x = CGFloat(index) * stepX
                        let ratio = min(1.0, max(0.0, (val - minVal) / range))
                        let y = canvasSize.height - (CGFloat(ratio) * (canvasSize.height - 4)) - 2
                        points.append(CGPoint(x: x, y: y))
                    }

                    var linePath = Path()
                    linePath.move(to: points[0])
                    for i in 1..<points.count {
                        let prev = points[i - 1]
                        let curr = points[i]
                        let midX = (prev.x + curr.x) * 0.5
                        linePath.addCurve(
                            to: curr,
                            control1: CGPoint(x: midX, y: prev.y),
                            control2: CGPoint(x: midX, y: curr.y)
                        )
                    }

                    var areaPath = linePath
                    areaPath.addLine(to: CGPoint(x: points.last!.x, y: canvasSize.height))
                    areaPath.addLine(to: CGPoint(x: points.first!.x, y: canvasSize.height))
                    areaPath.closeSubpath()

                    let gradient = Gradient(colors: [
                        lineColor.opacity(0.28),
                        lineColor.opacity(0.01)
                    ])
                    context.fill(
                        areaPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: canvasSize.height)
                        )
                    )

                    context.stroke(
                        linePath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                    if let idx = hoverIndex, idx < points.count {
                        let pt = points[idx]
                        var cursor = Path()
                        cursor.move(to: CGPoint(x: pt.x, y: 0))
                        cursor.addLine(to: CGPoint(x: pt.x, y: canvasSize.height))
                        context.stroke(
                            cursor,
                            with: .color(Color.primary.opacity(0.35)),
                            style: StrokeStyle(lineWidth: 0.75, dash: [2, 2])
                        )

                        let dotRect = CGRect(x: pt.x - 2.8, y: pt.y - 2.8, width: 5.6, height: 5.6)
                        context.fill(Path(ellipseIn: dotRect), with: .color(lineColor))
                        context.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.9)), lineWidth: 1)
                    }
                }

                if let idx = hoverIndex, idx < samples.count, let formatter = valueFormatter {
                    Text(formatter(samples[idx]))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                        .offset(x: tooltipOffsetX(idx: idx, count: samples.count, totalWidth: size.width), y: 0)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocationX = location.x
                case .ended:
                    hoverLocationX = nil
                }
            }
        }
    }

    private var normalizedSamples: [Double] {
        if values.count >= 2 { return values }
        if let first = values.first { return [first, first] }
        return [0, 0]
    }

    private func computeHoverIndex(width: CGFloat, count: Int) -> Int? {
        guard let x = hoverLocationX, width > 0, count >= 2 else { return nil }
        let ratio = min(1.0, max(0.0, x / width))
        return Int((ratio * CGFloat(count - 1)).rounded())
    }

    private func tooltipOffsetX(idx: Int, count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let ratio = CGFloat(idx) / CGFloat(count - 1)
        let rawX = ratio * totalWidth - 22
        return min(max(0, rawX), max(0, totalWidth - 52))
    }
}
