import BaroCore
import SwiftUI

public enum BaroPalette {
    public static let pCore = Color.indigo
    public static let eCore = Color.teal
    public static let download = Color(red: 0.20, green: 0.72, blue: 0.96)
    public static let upload = Color(red: 0.62, green: 0.45, blue: 0.98)
    public static let power = Color.orange
    public static let memoryApp = Color(red: 0.24, green: 0.60, blue: 0.98)
    public static let memoryWired = Color(red: 0.96, green: 0.62, blue: 0.18)
    public static let memoryCompressed = Color(red: 0.64, green: 0.48, blue: 0.96)
    public static let disk = Color(red: 0.35, green: 0.76, blue: 0.68)
    public static let batteryHealthy = Color(red: 0.20, green: 0.78, blue: 0.48)

    public static func healthColor(for level: HealthLevel) -> Color {
        switch level {
        case .calm:
            return Color(red: 0.20, green: 0.78, blue: 0.46)
        case .moderate:
            return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .elevated:
            return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }

    public static func thermalColor(celsius: Double) -> Color {
        if celsius >= 88 { return Color(red: 1.00, green: 0.27, blue: 0.23) }
        if celsius >= 72 { return Color(red: 1.00, green: 0.62, blue: 0.04) }
        return .primary
    }

    public static func usageColor(percent: Double) -> Color {
        if percent >= 85 { return Color(red: 1.00, green: 0.27, blue: 0.23) }
        if percent >= 60 { return Color(red: 1.00, green: 0.62, blue: 0.04) }
        return .primary
    }
}

public struct BaroLiquidGlassContainer: ViewModifier {
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 22) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        #if compiler(>=6.2) && canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            fallbackGlass(content)
        }
        #else
        fallbackGlass(content)
        #endif
    }

    private func fallbackGlass(_ content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            )
    }
}

public struct BentoCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var isExpanded: Bool = false

    public func body(content: Content) -> some View {
        let baseOpacity = colorScheme == .dark ? 0.065 : 0.048
        let borderOpacity = colorScheme == .dark ? (isExpanded ? 0.22 : 0.12) : (isExpanded ? 0.16 : 0.08)

        content
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(baseOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: 0.5)
            )
    }
}

public extension View {
    func baroLiquidGlass(cornerRadius: CGFloat = 22) -> some View {
        modifier(BaroLiquidGlassContainer(cornerRadius: cornerRadius))
    }

    func bentoCard(isExpanded: Bool = false) -> some View {
        modifier(BentoCardSurface(isExpanded: isExpanded))
    }
}
