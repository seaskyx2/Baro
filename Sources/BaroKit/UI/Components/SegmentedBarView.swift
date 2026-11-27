import SwiftUI

public struct ThinProgressBar: View {
    public let ratio: Double
    public let tint: Color
    public let height: CGFloat

    public init(ratio: Double, tint: Color, height: CGFloat = 5) {
        self.ratio = min(1.0, max(0.0, ratio))
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(ratio > 0 ? height : 0, geo.size.width * ratio))
                    .animation(.easeOut(duration: 0.25), value: ratio)
            }
        }
        .frame(height: height)
    }
}

public struct MemorySegment: Identifiable {
    public let id: String
    public let ratio: Double
    public let color: Color

    public init(id: String, ratio: Double, color: Color) {
        self.id = id
        self.ratio = max(0, ratio)
        self.color = color
    }
}

public struct SegmentedBarView: View {
    public let segments: [MemorySegment]
    public let height: CGFloat

    public init(segments: [MemorySegment], height: CGFloat = 6) {
        self.segments = segments
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                HStack(spacing: 1) {
                    ForEach(segments) { seg in
                        let segWidth = max(0, totalWidth * min(1.0, seg.ratio))
                        if segWidth > 0.5 {
                            Rectangle()
                                .fill(seg.color)
                                .frame(width: segWidth)
                        }
                    }
                }
                .clipShape(Capsule())
                .animation(.easeOut(duration: 0.25), value: segments.map(\.ratio))
            }
        }
        .frame(height: height)
    }
}
