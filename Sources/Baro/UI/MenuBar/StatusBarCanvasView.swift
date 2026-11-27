import AppKit
import BaroCore

/// 纯 AppKit / CoreGraphics 自绘状态栏视图：
/// 支持 5 种风格与 3 档间距密度，紧致排版零空隙冗余。
@MainActor
public final class StatusBarCanvasView: NSView {
    private var renderData: MenuBarRenderData = .empty
    private var style: MenuBarStyle = .compactDualRow
    private var density: MenuBarDensity = .compact
    private var showIcon: Bool = true
    private var showCPU: Bool = true
    private var showMemory: Bool = true
    private var showNetwork: Bool = true
    private var showTemperature: Bool = false
    private var showPower: Bool = false

    private let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    private let singleLineFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    private let singleLineDimFont = NSFont.systemFont(ofSize: 10.0, weight: .regular)

    private var cachedWidth: CGFloat = 104

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: cachedWidth, height: 22)
    }

    public func configure(data: MenuBarRenderData, settings: BaroSettings) -> CGFloat {
        self.renderData = data
        self.style = settings.menuBarStyle
        self.density = settings.menuBarDensity
        self.showIcon = settings.showMenuBarIcon
        self.showCPU = settings.showMenuCPU
        self.showMemory = settings.showMenuMemory
        self.showNetwork = settings.showMenuNetwork
        self.showTemperature = settings.showMenuTemperature
        self.showPower = settings.showMenuPower

        let targetWidth = computeFixedWidth()
        if abs(targetWidth - cachedWidth) >= 0.5 {
            cachedWidth = targetWidth
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
        return targetWidth
    }

    // MARK: - Density Spacing Tokens

    private var outerPadding: CGFloat {
        switch density {
        case .compact: return 3
        case .standard: return 5
        case .relaxed: return 7
        }
    }

    private var iconGap: CGFloat {
        switch density {
        case .compact: return 2.5
        case .standard: return 4.0
        case .relaxed: return 6.0
        }
    }

    private var groupGap: CGFloat {
        switch density {
        case .compact: return 4.0
        case .standard: return 6.5
        case .relaxed: return 9.5
        }
    }

    private func computeFixedWidth() -> CGFloat {
        var width: CGFloat = outerPadding * 2
        if showIcon {
            width += 12 + iconGap
        }

        switch style {
        case .compactDualRow:
            let hasLeft = showCPU || showMemory
            let hasMid = showNetwork
            let hasRight = showTemperature || showPower

            if !hasLeft && !hasMid && !hasRight {
                width += (showIcon ? 0 : 9) + 30
                return ceil(width)
            }

            var sections = 0
            if hasLeft {
                width += 46 // label 20 + gap 1 + value 25
                sections += 1
            }
            if hasMid {
                width += 38 // tight inline arrow+value
                sections += 1
            }
            if hasRight {
                width += 32 // temp / power
                sections += 1
            }
            if sections > 1 {
                width += CGFloat(sections - 1) * groupGap
            }

        case .singleLine:
            var parts = 0
            if showCPU { width += 32; parts += 1 }
            if showMemory { width += 32; parts += 1 }
            if showNetwork { width += 42; parts += 1 }
            if showTemperature { width += 28; parts += 1 }
            if showPower { width += 30; parts += 1 }
            if parts == 0 {
                width += 30
            } else if parts > 1 {
                width += CGFloat(parts - 1) * (density == .compact ? 6.0 : (density == .standard ? 8.5 : 11.0))
            }

        case .sparkline:
            width += 22 + iconGap + 27
            if showMemory {
                width += groupGap + 20 + 3 + 27
            }

        case .miniBars:
            // 两根精致垂直微柱 + 可选网速文字
            width += 13 // 5pt 柱 + 3pt 间距 + 5pt 柱
            if showCPU || showMemory {
                width += iconGap + 25
            }
            if showNetwork {
                width += groupGap + 38
            }

        case .breathingDot:
            width += 7 + iconGap + 27
            if renderData.healthLevel == .elevated, renderData.topCPUAppPath != nil {
                width += 13 + 3
            }
        }

        return ceil(width)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let primaryColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor

        var x: CGFloat = outerPadding

        if showIcon {
            let iconRect = NSRect(x: x, y: floor((bounds.height - 12) / 2.0), width: 12, height: 12)
            drawBarometerSymbol(in: iconRect, color: primaryColor)
            x += 12 + iconGap
        }

        switch style {
        case .compactDualRow:
            drawCompactDualRow(startX: x, bounds: bounds, primary: primaryColor, secondary: secondaryColor)
        case .singleLine:
            drawSingleLineStyle(startX: x, bounds: bounds, primary: primaryColor, secondary: secondaryColor)
        case .sparkline:
            drawSparklineStyle(startX: x, bounds: bounds, primary: primaryColor, secondary: secondaryColor)
        case .miniBars:
            drawMiniBarsStyle(startX: x, bounds: bounds, primary: primaryColor, secondary: secondaryColor)
        case .breathingDot:
            drawBreathingDotStyle(startX: x, bounds: bounds, primary: primaryColor)
        }
    }

    // MARK: - 矢量极简晴雨表小图标

    private func drawBarometerSymbol(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY - 0.7
        let r = rect.width * 0.44

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: cx, y: cy),
            radius: r,
            startAngle: -30,
            endAngle: 210,
            clockwise: false
        )
        arc.lineWidth = 1.35
        arc.lineCapStyle = .round
        color.withAlphaComponent(0.88).setStroke()
        arc.stroke()

        let angle = 48.0 * Double.pi / 180.0
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx, y: cy))
        needle.line(to: NSPoint(x: cx + cos(angle) * (r * 0.82), y: cy + sin(angle) * (r * 0.82)))
        needle.lineWidth = 1.3
        needle.lineCapStyle = .round
        color.setStroke()
        needle.stroke()

        let hubRect = NSRect(x: cx - 1.2, y: cy - 1.2, width: 2.4, height: 2.4)
        color.setFill()
        NSBezierPath(ovalIn: hubRect).fill()
    }

    // MARK: - 风格 1：双行精工

    private func drawCompactDualRow(startX: CGFloat, bounds: NSRect, primary: NSColor, secondary: NSColor) {
        var x = startX
        let hasLeft = showCPU || showMemory
        let hasMid = showNetwork
        let hasRight = showTemperature || showPower

        if !hasLeft && !hasMid && !hasRight {
            if !showIcon {
                healthNSColor(renderData.healthLevel).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: floor((bounds.height - 6) / 2), width: 6, height: 6)).fill()
                x += 9
            }
            drawSingleText("Baro", in: NSRect(x: x, y: 0, width: 30, height: bounds.height), font: singleLineFont, color: primary, alignment: .left)
            return
        }

        let topY = floor(bounds.height * 0.5) - 0.5
        let bottomY: CGFloat = 1.0
        let rowH: CGFloat = 10.5

        if hasLeft {
            if showCPU && showMemory {
                drawKVRow(label: "CPU", labelW: 20, value: "\(Int(renderData.cpuPercent.rounded()))%", valueW: 25, x: x, y: topY, h: rowH, labelColor: secondary, valueColor: usageNSColor(renderData.cpuPercent, fallback: primary))
                let memColor = renderData.memoryPressure == .normal ? primary : healthNSColor(.elevated)
                drawKVRow(label: "MEM", labelW: 20, value: "\(Int(renderData.memoryPercent.rounded()))%", valueW: 25, x: x, y: bottomY, h: rowH, labelColor: secondary, valueColor: memColor)
            } else if showCPU {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawKVRow(label: "CPU", labelW: 20, value: "\(Int(renderData.cpuPercent.rounded()))%", valueW: 25, x: x, y: midY, h: rowH, labelColor: secondary, valueColor: usageNSColor(renderData.cpuPercent, fallback: primary))
            } else if showMemory {
                let midY = floor((bounds.height - rowH) / 2.0)
                let memColor = renderData.memoryPressure == .normal ? primary : healthNSColor(.elevated)
                drawKVRow(label: "MEM", labelW: 20, value: "\(Int(renderData.memoryPercent.rounded()))%", valueW: 25, x: x, y: midY, h: rowH, labelColor: secondary, valueColor: memColor)
            }
            x += 46 + (hasMid || hasRight ? groupGap : 0)
        }

        if hasMid {
            drawTightInlineArrowRow(arrow: "↑", value: ByteFormatter.compactRate(renderData.uploadBytesPerSec), rect: NSRect(x: x, y: topY, width: 38, height: rowH), arrowColor: secondary, valueColor: primary)
            drawTightInlineArrowRow(arrow: "↓", value: ByteFormatter.compactRate(renderData.downloadBytesPerSec), rect: NSRect(x: x, y: bottomY, width: 38, height: rowH), arrowColor: secondary, valueColor: primary)
            x += 38 + (hasRight ? groupGap : 0)
        }

        if hasRight {
            let tempText = renderData.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "--°"
            let tempColor = renderData.temperatureCelsius.map { thermalNSColor($0, fallback: primary) } ?? secondary
            let powerText = renderData.isPowerAvailable ? String(format: "%.1fW", renderData.packageWatts) : "--W"

            if showTemperature && showPower {
                drawSingleText(tempText, in: NSRect(x: x, y: topY, width: 32, height: rowH), font: valueFont, color: tempColor, alignment: .right)
                drawSingleText(powerText, in: NSRect(x: x, y: bottomY, width: 32, height: rowH), font: valueFont, color: secondary, alignment: .right)
            } else if showTemperature {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawSingleText(tempText, in: NSRect(x: x, y: midY, width: 32, height: rowH), font: valueFont, color: tempColor, alignment: .right)
            } else if showPower {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawSingleText(powerText, in: NSRect(x: x, y: midY, width: 32, height: rowH), font: valueFont, color: secondary, alignment: .right)
            }
        }
    }

    // MARK: - 风格 2：单行清爽

    private func drawSingleLineStyle(startX: CGFloat, bounds: NSRect, primary: NSColor, secondary: NSColor) {
        var tokens: [(prefix: String, value: String, width: CGFloat, color: NSColor)] = []
        if showCPU {
            tokens.append(("C ", "\(Int(renderData.cpuPercent.rounded()))%", 32, usageNSColor(renderData.cpuPercent, fallback: primary)))
        }
        if showMemory {
            let memColor = renderData.memoryPressure == .normal ? primary : healthNSColor(.elevated)
            tokens.append(("M ", "\(Int(renderData.memoryPercent.rounded()))%", 32, memColor))
        }
        if showNetwork {
            tokens.append(("↓", ByteFormatter.compactRate(renderData.downloadBytesPerSec), 42, primary))
        }
        if showTemperature {
            let t = renderData.temperatureCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
            let c = renderData.temperatureCelsius.map { thermalNSColor($0, fallback: primary) } ?? secondary
            tokens.append(("", t, 28, c))
        }
        if showPower {
            let p = renderData.isPowerAvailable ? String(format: "%.0fW", renderData.packageWatts) : "--W"
            tokens.append(("", p, 30, secondary))
        }

        if tokens.isEmpty {
            drawSingleText("Baro", in: NSRect(x: startX, y: 0, width: 30, height: bounds.height), font: singleLineFont, color: primary, alignment: .left)
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
                drawSingleText("·", in: NSRect(x: x, y: 0, width: sepW, height: bounds.height), font: singleLineDimFont, color: secondary.withAlphaComponent(0.55), alignment: .center)
                x += sepW
            }
        }
    }

    // MARK: - 风格 3：微图表

    private func drawSparklineStyle(startX: CGFloat, bounds: NSRect, primary: NSColor, secondary: NSColor) {
        var x = startX
        let chartRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 22, height: 13)
        let pts = renderData.cpuSparklinePoints.count >= 2 ? renderData.cpuSparklinePoints : [0, 0]
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
        path.lineWidth = 1.25
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        primary.withAlphaComponent(0.85).setStroke()
        path.stroke()
        x += 22 + iconGap

        let cpuText = "\(Int(renderData.cpuPercent.rounded()))%"
        drawSingleText(cpuText, in: NSRect(x: x, y: 0, width: 27, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
        x += 27

        if showMemory {
            x += groupGap
            let capRect = NSRect(x: x, y: floor((bounds.height - 7) / 2.0), width: 20, height: 7)
            primary.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: capRect, xRadius: 2.5, yRadius: 2.5).fill()

            let ratio = min(1.0, max(0.0, renderData.memoryPercent / 100.0))
            let fillW = max(2.0, capRect.width * ratio)
            let fillRect = NSRect(x: capRect.minX, y: capRect.minY, width: fillW, height: capRect.height)
            primary.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill()
            x += 20 + 3

            let memText = "\(Int(renderData.memoryPercent.rounded()))%"
            drawSingleText(memText, in: NSRect(x: x, y: 0, width: 27, height: bounds.height), font: singleLineFont, color: secondary, alignment: .right)
        }
    }

    // MARK: - 风格 4：双柱仪表（极省刘海屏空间）

    private func drawMiniBarsStyle(startX: CGFloat, bounds: NSRect, primary: NSColor, secondary: NSColor) {
        var x = startX
        let barW: CGFloat = 5.0
        let barH: CGFloat = 13.0
        let barY = floor((bounds.height - barH) / 2.0)

        drawVerticalBar(
            in: NSRect(x: x, y: barY, width: barW, height: barH),
            ratio: renderData.cpuPercent / 100.0,
            fillColor: usageNSColor(renderData.cpuPercent, fallback: NSColor.systemIndigo),
            trackColor: primary.withAlphaComponent(0.18)
        )
        drawVerticalBar(
            in: NSRect(x: x + barW + 3, y: barY, width: barW, height: barH),
            ratio: renderData.memoryPercent / 100.0,
            fillColor: renderData.memoryPressure == .normal ? NSColor.systemTeal : healthNSColor(.elevated),
            trackColor: primary.withAlphaComponent(0.18)
        )
        x += 13

        if showCPU || showMemory {
            x += iconGap
            let topY = floor(bounds.height * 0.5) - 0.5
            let bottomY: CGFloat = 1.0
            let rowH: CGFloat = 10.5
            if showCPU && showMemory {
                drawSingleText("\(Int(renderData.cpuPercent.rounded()))%", in: NSRect(x: x, y: topY, width: 25, height: rowH), font: valueFont, color: primary, alignment: .right)
                drawSingleText("\(Int(renderData.memoryPercent.rounded()))%", in: NSRect(x: x, y: bottomY, width: 25, height: rowH), font: valueFont, color: secondary, alignment: .right)
            } else {
                let pct = showCPU ? renderData.cpuPercent : renderData.memoryPercent
                drawSingleText("\(Int(pct.rounded()))%", in: NSRect(x: x, y: 0, width: 25, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
            }
            x += 25
        }

        if showNetwork {
            x += groupGap
            let topY = floor(bounds.height * 0.5) - 0.5
            let bottomY: CGFloat = 1.0
            let rowH: CGFloat = 10.5
            drawTightInlineArrowRow(arrow: "↑", value: ByteFormatter.compactRate(renderData.uploadBytesPerSec), rect: NSRect(x: x, y: topY, width: 38, height: rowH), arrowColor: secondary, valueColor: primary)
            drawTightInlineArrowRow(arrow: "↓", value: ByteFormatter.compactRate(renderData.downloadBytesPerSec), rect: NSRect(x: x, y: bottomY, width: 38, height: rowH), arrowColor: secondary, valueColor: primary)
        }
    }

    private func drawVerticalBar(in rect: NSRect, ratio: Double, fillColor: NSColor, trackColor: NSColor) {
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()

        let clamped = min(1.0, max(0.0, ratio))
        let fillH = max(2.0, rect.height * clamped)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fillH)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    // MARK: - 风格 5：静默呼吸点

    private func drawBreathingDotStyle(startX: CGFloat, bounds: NSRect, primary: NSColor) {
        var x = startX
        let dotRect = NSRect(x: x, y: floor((bounds.height - 7) / 2.0), width: 7, height: 7)
        healthNSColor(renderData.healthLevel).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        x += 7 + iconGap

        if renderData.healthLevel == .elevated, let path = renderData.topCPUAppPath {
            let icon = AppIconCache.shared.icon(forAppPath: path)
            let iconRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 13, height: 13)
            icon.draw(in: iconRect)
            x += 13 + 3
        }

        let cpuText = "\(Int(renderData.cpuPercent.rounded()))%"
        drawSingleText(cpuText, in: NSRect(x: x, y: 0, width: 27, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
    }

    // MARK: - Drawing Helpers

    private func drawKVRow(
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

    /// 让箭头紧贴速率数字（解决 ↑ 与 0B 之间空隙过大的视觉问题）
    private func drawTightInlineArrowRow(
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

    private func drawSingleText(
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

    private func healthNSColor(_ level: HealthLevel) -> NSColor {
        switch level {
        case .calm: return NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.46, alpha: 1.0)
        case .moderate: return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 1.0)
        case .elevated: return NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1.0)
        }
    }

    private func usageNSColor(_ percent: Double, fallback: NSColor) -> NSColor {
        if percent >= 85 { return NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1.0) }
        if percent >= 60 { return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 1.0) }
        return fallback
    }

    private func thermalNSColor(_ celsius: Double, fallback: NSColor) -> NSColor {
        if celsius >= 88 { return NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1.0) }
        if celsius >= 72 { return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 1.0) }
        return fallback
    }
}
