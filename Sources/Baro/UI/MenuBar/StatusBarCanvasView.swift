import AppKit
import BaroCore

/// 原生菜单栏高清渲染器：
/// - 常规单色态生成 `isTemplate = true` 的高清矢量/Retina 图像，交由 macOS WindowServer 与 Liquid Glass
///   按底层壁纸实时反色与锐化（清晰度与系统时钟/Wi-Fi 完全一致）；
/// - 含语义彩色状态（如呼吸点或红/黄高负载提示）时，依据菜单栏外观采用 100% 纯白/纯黑高对比字体。
@MainActor
public enum MenuBarImageRenderer {
    private static let labelFont = NSFont.systemFont(ofSize: 9.0, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .bold)
    private static let singleLineFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
    private static let singleLineDimFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)

    public static func render(
        data: MenuBarRenderData,
        settings: BaroSettings,
        appearance: NSAppearance
    ) -> NSImage {
        let style = settings.menuBarStyle
        let density = settings.menuBarDensity
        let showIcon = settings.showMenuBarIcon
        let showCPU = settings.showMenuCPU
        let showMemory = settings.showMenuMemory
        let showNetwork = settings.showMenuNetwork
        let showTemperature = settings.showMenuTemperature
        let showPower = settings.showMenuPower

        let outerPad = outerPadding(for: density)
        let iconGap = Self.iconGap(for: density)
        let groupGap = Self.groupGap(for: density)

        let totalWidth = computeWidth(
            data: data,
            style: style,
            density: density,
            showIcon: showIcon,
            showCPU: showCPU,
            showMemory: showMemory,
            showNetwork: showNetwork,
            showTemperature: showTemperature,
            showPower: showPower
        )

        let hasColorAccent = needsColorRendering(
            data: data,
            style: style,
            showCPU: showCPU,
            showMemory: showMemory,
            showTemperature: showTemperature
        )

        let isDarkMenuBar = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let primaryColor: NSColor
        let secondaryColor: NSColor
        if hasColorAccent {
            primaryColor = isDarkMenuBar ? .white : .black
            secondaryColor = isDarkMenuBar
                ? NSColor.white.withAlphaComponent(0.84)
                : NSColor.black.withAlphaComponent(0.78)
        } else {
            // isTemplate = true 时使用纯黑 alpha 绘制，由系统自动按壁纸/玻璃着色与反色
            primaryColor = NSColor.black
            secondaryColor = NSColor.black.withAlphaComponent(0.82)
        }

        let size = NSSize(width: totalWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { bounds in
            var x = outerPad

            if showIcon {
                let iconRect = NSRect(x: x, y: floor((bounds.height - 12.5) / 2.0), width: 12.5, height: 12.5)
                drawBarometerSymbol(in: iconRect, color: primaryColor)
                x += 12.5 + iconGap
            }

            switch style {
            case .compactDualRow:
                drawCompactDualRow(
                    startX: x,
                    bounds: bounds,
                    groupGap: groupGap,
                    data: data,
                    showIcon: showIcon,
                    showCPU: showCPU,
                    showMemory: showMemory,
                    showNetwork: showNetwork,
                    showTemperature: showTemperature,
                    showPower: showPower,
                    primary: primaryColor,
                    secondary: secondaryColor
                )
            case .singleLine:
                drawSingleLineStyle(
                    startX: x,
                    bounds: bounds,
                    density: density,
                    data: data,
                    showCPU: showCPU,
                    showMemory: showMemory,
                    showNetwork: showNetwork,
                    showTemperature: showTemperature,
                    showPower: showPower,
                    primary: primaryColor,
                    secondary: secondaryColor
                )
            case .sparkline:
                drawSparklineStyle(
                    startX: x,
                    bounds: bounds,
                    iconGap: iconGap,
                    groupGap: groupGap,
                    data: data,
                    showMemory: showMemory,
                    primary: primaryColor,
                    secondary: secondaryColor
                )
            case .miniBars:
                drawMiniBarsStyle(
                    startX: x,
                    bounds: bounds,
                    iconGap: iconGap,
                    groupGap: groupGap,
                    data: data,
                    showCPU: showCPU,
                    showMemory: showMemory,
                    showNetwork: showNetwork,
                    primary: primaryColor,
                    secondary: secondaryColor
                )
            case .breathingDot:
                drawBreathingDotStyle(
                    startX: x,
                    bounds: bounds,
                    iconGap: iconGap,
                    data: data,
                    primary: primaryColor
                )
            }

            return true
        }

        image.isTemplate = !hasColorAccent
        return image
    }

    private static func needsColorRendering(
        data: MenuBarRenderData,
        style: MenuBarStyle,
        showCPU: Bool,
        showMemory: Bool,
        showTemperature: Bool
    ) -> Bool {
        switch style {
        case .breathingDot, .miniBars:
            return true
        case .sparkline:
            return false
        case .compactDualRow, .singleLine:
            if showCPU && data.cpuPercent >= 60 { return true }
            if showMemory && data.memoryPressure != .normal { return true }
            if showTemperature, let t = data.temperatureCelsius, t >= 72 { return true }
            return false
        }
    }

    // MARK: - Spacing & Sizing

    private static func outerPadding(for density: MenuBarDensity) -> CGFloat {
        switch density {
        case .compact: return 3
        case .standard: return 5
        case .relaxed: return 7
        }
    }

    private static func iconGap(for density: MenuBarDensity) -> CGFloat {
        switch density {
        case .compact: return 3.0
        case .standard: return 4.5
        case .relaxed: return 6.5
        }
    }

    private static func groupGap(for density: MenuBarDensity) -> CGFloat {
        switch density {
        case .compact: return 5.0
        case .standard: return 7.5
        case .relaxed: return 10.5
        }
    }

    private static func computeWidth(
        data: MenuBarRenderData,
        style: MenuBarStyle,
        density: MenuBarDensity,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool
    ) -> CGFloat {
        var width: CGFloat = outerPadding(for: density) * 2
        let iGap = iconGap(for: density)
        let gGap = groupGap(for: density)

        if showIcon {
            width += 12.5 + iGap
        }

        switch style {
        case .compactDualRow:
            let hasLeft = showCPU || showMemory
            let hasMid = showNetwork
            let hasRight = showTemperature || showPower

            if !hasLeft && !hasMid && !hasRight {
                width += (showIcon ? 0 : 9) + 32
                return ceil(width)
            }

            var sections = 0
            if hasLeft {
                width += 49 // label 22 + gap 1 + value 26
                sections += 1
            }
            if hasMid {
                width += 40 // tight inline arrow+rate
                sections += 1
            }
            if hasRight {
                width += 34
                sections += 1
            }
            if sections > 1 {
                width += CGFloat(sections - 1) * gGap
            }

        case .singleLine:
            var parts = 0
            if showCPU { width += 35; parts += 1 }
            if showMemory { width += 35; parts += 1 }
            if showNetwork { width += 44; parts += 1 }
            if showTemperature { width += 30; parts += 1 }
            if showPower { width += 32; parts += 1 }
            if parts == 0 {
                width += 32
            } else if parts > 1 {
                width += CGFloat(parts - 1) * (density == .compact ? 6.0 : (density == .standard ? 8.5 : 11.0))
            }

        case .sparkline:
            width += 22 + iGap + 29
            if showMemory {
                width += gGap + 20 + 3 + 29
            }

        case .miniBars:
            width += 13
            if showCPU || showMemory {
                width += iGap + 27
            }
            if showNetwork {
                width += gGap + 40
            }

        case .breathingDot:
            width += 7 + iGap + 29
            if data.healthLevel == .elevated, data.topCPUAppPath != nil {
                width += 13 + 3
            }
        }

        return ceil(width)
    }

    // MARK: - Symbol

    private static func drawBarometerSymbol(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY - 0.7
        let r = rect.width * 0.44

        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: -30, endAngle: 210, clockwise: false)
        arc.lineWidth = 1.45
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()

        let angle = 48.0 * Double.pi / 180.0
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx, y: cy))
        needle.line(to: NSPoint(x: cx + cos(angle) * (r * 0.84), y: cy + sin(angle) * (r * 0.84)))
        needle.lineWidth = 1.4
        needle.lineCapStyle = .round
        color.setStroke()
        needle.stroke()

        let hubRect = NSRect(x: cx - 1.25, y: cy - 1.25, width: 2.5, height: 2.5)
        color.setFill()
        NSBezierPath(ovalIn: hubRect).fill()
    }

    // MARK: - Style 1: Compact Dual Row

    private static func drawCompactDualRow(
        startX: CGFloat,
        bounds: NSRect,
        groupGap: CGFloat,
        data: MenuBarRenderData,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool,
        primary: NSColor,
        secondary: NSColor
    ) {
        var x = startX
        let hasLeft = showCPU || showMemory
        let hasMid = showNetwork
        let hasRight = showTemperature || showPower

        if !hasLeft && !hasMid && !hasRight {
            if !showIcon {
                primary.setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: floor((bounds.height - 6) / 2), width: 6, height: 6)).fill()
                x += 9
            }
            drawSingleText("Baro", in: NSRect(x: x, y: 0, width: 32, height: bounds.height), font: singleLineFont, color: primary, alignment: .left)
            return
        }

        let topY = floor(bounds.height * 0.5) - 0.5
        let bottomY: CGFloat = 0.5
        let rowH: CGFloat = 11.0

        if hasLeft {
            if showCPU && showMemory {
                drawKVRow(label: "CPU", labelW: 22, value: "\(Int(data.cpuPercent.rounded()))%", valueW: 26, x: x, y: topY, h: rowH, labelColor: secondary, valueColor: usageNSColor(data.cpuPercent, fallback: primary))
                let memColor = data.memoryPressure == .normal ? primary : healthNSColor(.elevated)
                drawKVRow(label: "MEM", labelW: 22, value: "\(Int(data.memoryPercent.rounded()))%", valueW: 26, x: x, y: bottomY, h: rowH, labelColor: secondary, valueColor: memColor)
            } else if showCPU {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawKVRow(label: "CPU", labelW: 22, value: "\(Int(data.cpuPercent.rounded()))%", valueW: 26, x: x, y: midY, h: rowH, labelColor: secondary, valueColor: usageNSColor(data.cpuPercent, fallback: primary))
            } else if showMemory {
                let midY = floor((bounds.height - rowH) / 2.0)
                let memColor = data.memoryPressure == .normal ? primary : healthNSColor(.elevated)
                drawKVRow(label: "MEM", labelW: 22, value: "\(Int(data.memoryPercent.rounded()))%", valueW: 26, x: x, y: midY, h: rowH, labelColor: secondary, valueColor: memColor)
            }
            x += 49 + (hasMid || hasRight ? groupGap : 0)
        }

        if hasMid {
            drawTightInlineArrowRow(arrow: "↑", value: ByteFormatter.compactRate(data.uploadBytesPerSec), rect: NSRect(x: x, y: topY, width: 40, height: rowH), arrowColor: secondary, valueColor: primary)
            drawTightInlineArrowRow(arrow: "↓", value: ByteFormatter.compactRate(data.downloadBytesPerSec), rect: NSRect(x: x, y: bottomY, width: 40, height: rowH), arrowColor: secondary, valueColor: primary)
            x += 40 + (hasRight ? groupGap : 0)
        }

        if hasRight {
            let tempText = data.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "--°"
            let tempColor = data.temperatureCelsius.map { thermalNSColor($0, fallback: primary) } ?? secondary
            let powerText = data.isPowerAvailable ? String(format: "%.1fW", data.packageWatts) : "--W"

            if showTemperature && showPower {
                drawSingleText(tempText, in: NSRect(x: x, y: topY, width: 34, height: rowH), font: valueFont, color: tempColor, alignment: .right)
                drawSingleText(powerText, in: NSRect(x: x, y: bottomY, width: 34, height: rowH), font: valueFont, color: secondary, alignment: .right)
            } else if showTemperature {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawSingleText(tempText, in: NSRect(x: x, y: midY, width: 34, height: rowH), font: valueFont, color: tempColor, alignment: .right)
            } else if showPower {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawSingleText(powerText, in: NSRect(x: x, y: midY, width: 34, height: rowH), font: valueFont, color: secondary, alignment: .right)
            }
        }
    }

    // MARK: - Style 2: Single Line

    private static func drawSingleLineStyle(
        startX: CGFloat,
        bounds: NSRect,
        density: MenuBarDensity,
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool,
        primary: NSColor,
        secondary: NSColor
    ) {
        var tokens: [(prefix: String, value: String, width: CGFloat, color: NSColor)] = []
        if showCPU {
            tokens.append(("C ", "\(Int(data.cpuPercent.rounded()))%", 35, usageNSColor(data.cpuPercent, fallback: primary)))
        }
        if showMemory {
            let memColor = data.memoryPressure == .normal ? primary : healthNSColor(.elevated)
            tokens.append(("M ", "\(Int(data.memoryPercent.rounded()))%", 35, memColor))
        }
        if showNetwork {
            tokens.append(("↓", ByteFormatter.compactRate(data.downloadBytesPerSec), 44, primary))
        }
        if showTemperature {
            let t = data.temperatureCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
            let c = data.temperatureCelsius.map { thermalNSColor($0, fallback: primary) } ?? secondary
            tokens.append(("", t, 30, c))
        }
        if showPower {
            let p = data.isPowerAvailable ? String(format: "%.0fW", data.packageWatts) : "--W"
            tokens.append(("", p, 32, secondary))
        }

        if tokens.isEmpty {
            drawSingleText("Baro", in: NSRect(x: startX, y: 0, width: 32, height: bounds.height), font: singleLineFont, color: primary, alignment: .left)
            return
        }

        let sepW: CGFloat = density == .compact ? 6.0 : (density == .standard ? 8.5 : 11.0)
        var x = startX
        for (idx, item) in tokens.enumerated() {
            let attr = NSMutableAttributedString()
            if !item.prefix.isEmpty {
                attr.append(NSAttributedString(string: item.prefix, attributes: [.font: labelFont, .foregroundColor: secondary]))
            }
            attr.append(NSAttributedString(string: item.value, attributes: [.font: singleLineFont, .foregroundColor: item.color]))

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byClipping
            attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))

            let size = attr.size()
            let cy = floor((bounds.height - size.height) / 2.0)
            attr.draw(in: NSRect(x: x, y: cy, width: item.width, height: size.height))
            x += item.width

            if idx < tokens.count - 1 {
                drawSingleText("·", in: NSRect(x: x, y: 0, width: sepW, height: bounds.height), font: singleLineDimFont, color: secondary, alignment: .center)
                x += sepW
            }
        }
    }

    // MARK: - Style 3: Sparkline

    private static func drawSparklineStyle(
        startX: CGFloat,
        bounds: NSRect,
        iconGap: CGFloat,
        groupGap: CGFloat,
        data: MenuBarRenderData,
        showMemory: Bool,
        primary: NSColor,
        secondary: NSColor
    ) {
        var x = startX
        let chartRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 22, height: 13)
        let pts = data.cpuSparklinePoints.count >= 2 ? data.cpuSparklinePoints : [0, 0]
        let path = NSBezierPath()
        let stepX = chartRect.width / CGFloat(pts.count - 1)
        for (idx, val) in pts.enumerated() {
            let px = chartRect.minX + CGFloat(idx) * stepX
            let ratio = min(1.0, max(0.0, val / 100.0))
            let py = chartRect.minY + 1 + CGFloat(ratio) * (chartRect.height - 2)
            if idx == 0 {
                path.move(to: NSPoint(x: px, y: py))
            } else {
                path.line(to: NSPoint(x: px, y: py))
            }
        }
        path.lineWidth = 1.35
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        primary.setStroke()
        path.stroke()
        x += 22 + iconGap

        let cpuText = "\(Int(data.cpuPercent.rounded()))%"
        drawSingleText(cpuText, in: NSRect(x: x, y: 0, width: 29, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
        x += 29

        if showMemory {
            x += groupGap
            let capRect = NSRect(x: x, y: floor((bounds.height - 7) / 2.0), width: 20, height: 7)
            primary.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: capRect, xRadius: 2.5, yRadius: 2.5).fill()

            let ratio = min(1.0, max(0.0, data.memoryPercent / 100.0))
            let fillW = max(2.5, capRect.width * ratio)
            let fillRect = NSRect(x: capRect.minX, y: capRect.minY, width: fillW, height: capRect.height)
            primary.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill()
            x += 20 + 3

            let memText = "\(Int(data.memoryPercent.rounded()))%"
            drawSingleText(memText, in: NSRect(x: x, y: 0, width: 29, height: bounds.height), font: singleLineFont, color: secondary, alignment: .right)
        }
    }

    // MARK: - Style 4: Mini Bars

    private static func drawMiniBarsStyle(
        startX: CGFloat,
        bounds: NSRect,
        iconGap: CGFloat,
        groupGap: CGFloat,
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        primary: NSColor,
        secondary: NSColor
    ) {
        var x = startX
        let barW: CGFloat = 5.0
        let barH: CGFloat = 13.0
        let barY = floor((bounds.height - barH) / 2.0)

        drawVerticalBar(
            in: NSRect(x: x, y: barY, width: barW, height: barH),
            ratio: data.cpuPercent / 100.0,
            fillColor: usageNSColor(data.cpuPercent, fallback: NSColor.systemIndigo),
            trackColor: primary.withAlphaComponent(0.24)
        )
        drawVerticalBar(
            in: NSRect(x: x + barW + 3, y: barY, width: barW, height: barH),
            ratio: data.memoryPercent / 100.0,
            fillColor: data.memoryPressure == .normal ? NSColor.systemTeal : healthNSColor(.elevated),
            trackColor: primary.withAlphaComponent(0.24)
        )
        x += 13

        if showCPU || showMemory {
            x += iconGap
            let topY = floor(bounds.height * 0.5) - 0.5
            let bottomY: CGFloat = 0.5
            let rowH: CGFloat = 11.0
            if showCPU && showMemory {
                drawSingleText("\(Int(data.cpuPercent.rounded()))%", in: NSRect(x: x, y: topY, width: 27, height: rowH), font: valueFont, color: primary, alignment: .right)
                drawSingleText("\(Int(data.memoryPercent.rounded()))%", in: NSRect(x: x, y: bottomY, width: 27, height: rowH), font: valueFont, color: secondary, alignment: .right)
            } else {
                let pct = showCPU ? data.cpuPercent : data.memoryPercent
                drawSingleText("\(Int(pct.rounded()))%", in: NSRect(x: x, y: 0, width: 27, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
            }
            x += 27
        }

        if showNetwork {
            x += groupGap
            let topY = floor(bounds.height * 0.5) - 0.5
            let bottomY: CGFloat = 0.5
            let rowH: CGFloat = 11.0
            drawTightInlineArrowRow(arrow: "↑", value: ByteFormatter.compactRate(data.uploadBytesPerSec), rect: NSRect(x: x, y: topY, width: 40, height: rowH), arrowColor: secondary, valueColor: primary)
            drawTightInlineArrowRow(arrow: "↓", value: ByteFormatter.compactRate(data.downloadBytesPerSec), rect: NSRect(x: x, y: bottomY, width: 40, height: rowH), arrowColor: secondary, valueColor: primary)
        }
    }

    private static func drawVerticalBar(in rect: NSRect, ratio: Double, fillColor: NSColor, trackColor: NSColor) {
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()

        let clamped = min(1.0, max(0.0, ratio))
        let fillH = max(2.5, rect.height * clamped)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fillH)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    // MARK: - Style 5: Breathing Dot

    private static func drawBreathingDotStyle(
        startX: CGFloat,
        bounds: NSRect,
        iconGap: CGFloat,
        data: MenuBarRenderData,
        primary: NSColor
    ) {
        var x = startX
        let dotRect = NSRect(x: x, y: floor((bounds.height - 7.5) / 2.0), width: 7.5, height: 7.5)
        healthNSColor(data.healthLevel).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        x += 7.5 + iconGap

        if data.healthLevel == .elevated, let path = data.topCPUAppPath {
            let icon = AppIconCache.shared.icon(forAppPath: path)
            let iconRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 13, height: 13)
            icon.draw(in: iconRect)
            x += 13 + 3
        }

        let cpuText = "\(Int(data.cpuPercent.rounded()))%"
        drawSingleText(cpuText, in: NSRect(x: x, y: 0, width: 29, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
    }

    // MARK: - Drawing Helpers

    private static func drawKVRow(
        label: String,
        labelW: CGFloat,
        value: String,
        valueW: CGFloat,
        x: CGFloat,
        y: CGFloat,
        h: CGFloat,
        labelColor: NSColor,
        valueColor: NSColor
    ) {
        drawSingleText(label, in: NSRect(x: x, y: y, width: labelW, height: h), font: labelFont, color: labelColor, alignment: .left)
        drawSingleText(value, in: NSRect(x: x + labelW + 1, y: y, width: valueW, height: h), font: valueFont, color: valueColor, alignment: .right)
    }

    private static func drawTightInlineArrowRow(
        arrow: String,
        value: String,
        rect: NSRect,
        arrowColor: NSColor,
        valueColor: NSColor
    ) {
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: arrow, attributes: [.font: labelFont, .foregroundColor: arrowColor]))
        attr.append(NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: valueColor]))

        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.lineBreakMode = .byClipping
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))

        let size = attr.size()
        let centeredY = rect.minY + floor((rect.height - size.height) / 2.0)
        attr.draw(in: NSRect(x: rect.minX, y: centeredY, width: rect.width, height: size.height))
    }

    private static func drawSingleText(
        _ string: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let attrStr = NSAttributedString(string: string, attributes: attrs)
        let size = attrStr.size()
        let centeredY = rect.minY + floor((rect.height - size.height) / 2.0)
        let drawRect = NSRect(x: rect.minX, y: centeredY, width: rect.width, height: size.height)
        attrStr.draw(in: drawRect)
    }

    private static func healthNSColor(_ level: HealthLevel) -> NSColor {
        switch level {
        case .calm: return NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.48, alpha: 1.0)
        case .moderate: return NSColor(calibratedRed: 1.00, green: 0.65, blue: 0.10, alpha: 1.0)
        case .elevated: return NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.25, alpha: 1.0)
        }
    }

    private static func usageNSColor(_ percent: Double, fallback: NSColor) -> NSColor {
        if percent >= 85 { return NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.25, alpha: 1.0) }
        if percent >= 60 { return NSColor(calibratedRed: 1.00, green: 0.65, blue: 0.10, alpha: 1.0) }
        return fallback
    }

    private static func thermalNSColor(_ celsius: Double, fallback: NSColor) -> NSColor {
        if celsius >= 88 { return NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.25, alpha: 1.0) }
        if celsius >= 72 { return NSColor(calibratedRed: 1.00, green: 0.65, blue: 0.10, alpha: 1.0) }
        return fallback
    }
}
