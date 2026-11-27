import AppKit
import BaroCore

/// 纯 AppKit / CoreGraphics 自绘状态栏视图：
/// 零 SwiftUI 渲染树常驻，极致压低冷态内存与 CPU 占用。
@MainActor
public final class StatusBarCanvasView: NSView {
    private var renderData: MenuBarRenderData = .empty
    private var style: MenuBarStyle = .compactDualRow
    private var showIcon: Bool = true
    private var showCPU: Bool = true
    private var showMemory: Bool = true
    private var showNetwork: Bool = true
    private var showTemperature: Bool = false
    private var showPower: Bool = false

    private let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    private let singleLineFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

    private var cachedWidth: CGFloat = 116

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

    private func computeFixedWidth() -> CGFloat {
        var width: CGFloat = 12 // 左右各 6pt 内边距
        if showIcon {
            width += 17 // 13pt 矢量晴雨表小图标 + 4pt 间距
        }

        switch style {
        case .compactDualRow:
            let hasLeft = showCPU || showMemory
            let hasMid = showNetwork
            let hasRight = showTemperature || showPower

            if !hasLeft && !hasMid && !hasRight {
                width += 36 // "Baro" 文字
                return ceil(width)
            }

            var sections = 0
            if hasLeft {
                width += 56 // label 23 + spacing 2 + value 31
                sections += 1
            }
            if hasMid {
                width += 47 // arrow 9 + spacing 2 + value 36
                sections += 1
            }
            if hasRight {
                width += 38 // temp / power
                sections += 1
            }
            if sections > 1 {
                width += CGFloat(sections - 1) * 7
            }

        case .sparkline:
            width += 24 + 5 + 31 // sparkline 24 + gap 5 + cpu% 31
            if showMemory {
                width += 6 + 22 + 4 + 31 // gap + capsule + gap + mem%
            }

        case .breathingDot:
            width += 7 + 5 + 31 // dot + gap + cpu%
            if renderData.healthLevel == .elevated, renderData.topCPUAppPath != nil {
                width += 13 + 4 // app icon + gap
            }
        }

        return ceil(width)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let primaryColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor

        var x: CGFloat = 6

        if showIcon {
            let iconRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 13, height: 13)
            drawBarometerSymbol(in: iconRect, color: primaryColor)
            x += 17
        }

        switch style {
        case .compactDualRow:
            drawCompactDualRow(startX: x, bounds: bounds, primary: primaryColor, secondary: secondaryColor)
        case .sparkline:
            drawSparklineStyle(startX: x, bounds: bounds, primary: primaryColor, secondary: secondaryColor)
        case .breathingDot:
            drawBreathingDotStyle(startX: x, bounds: bounds, primary: primaryColor)
        }
    }

    // MARK: - 矢量极简晴雨表小图标

    private func drawBarometerSymbol(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY - 0.8
        let r = rect.width * 0.44

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: cx, y: cy),
            radius: r,
            startAngle: -30,
            endAngle: 210,
            clockwise: false
        )
        arc.lineWidth = 1.4
        arc.lineCapStyle = .round
        color.withAlphaComponent(0.88).setStroke()
        arc.stroke()

        // 指针指向舒适偏右上刻度（约 50°）
        let angle = 48.0 * Double.pi / 180.0
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx, y: cy))
        needle.line(to: NSPoint(x: cx + cos(angle) * (r * 0.82), y: cy + sin(angle) * (r * 0.82)))
        needle.lineWidth = 1.35
        needle.lineCapStyle = .round
        color.setStroke()
        needle.stroke()

        let hubRect = NSRect(x: cx - 1.3, y: cy - 1.3, width: 2.6, height: 2.6)
        color.setFill()
        NSBezierPath(ovalIn: hubRect).fill()
    }

    // MARK: - 风格 A：双行精工

    private func drawCompactDualRow(startX: CGFloat, bounds: NSRect, primary: NSColor, secondary: NSColor) {
        var x = startX
        let hasLeft = showCPU || showMemory
        let hasMid = showNetwork
        let hasRight = showTemperature || showPower

        if !hasLeft && !hasMid && !hasRight {
            let dotColor = healthNSColor(renderData.healthLevel)
            if !showIcon {
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: floor((bounds.height - 6) / 2), width: 6, height: 6)).fill()
                x += 10
            }
            drawSingleText("Baro", in: NSRect(x: x, y: 0, width: 30, height: bounds.height), font: singleLineFont, color: primary, alignment: .left)
            return
        }

        let topY = floor(bounds.height * 0.5) - 0.5
        let bottomY: CGFloat = 1.0
        let rowH: CGFloat = 10.5

        if hasLeft {
            if showCPU && showMemory {
                drawKVRow(label: "CPU", labelW: 23, value: "\(Int(renderData.cpuPercent.rounded()))%", valueW: 31, x: x, y: topY, h: rowH, labelColor: secondary, valueColor: usageNSColor(renderData.cpuPercent, fallback: primary))
                let memColor = renderData.memoryPressure == .normal ? primary : healthNSColor(.elevated)
                drawKVRow(label: "MEM", labelW: 23, value: "\(Int(renderData.memoryPercent.rounded()))%", valueW: 31, x: x, y: bottomY, h: rowH, labelColor: secondary, valueColor: memColor)
            } else if showCPU {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawKVRow(label: "CPU", labelW: 23, value: "\(Int(renderData.cpuPercent.rounded()))%", valueW: 31, x: x, y: midY, h: rowH, labelColor: secondary, valueColor: usageNSColor(renderData.cpuPercent, fallback: primary))
            } else if showMemory {
                let midY = floor((bounds.height - rowH) / 2.0)
                let memColor = renderData.memoryPressure == .normal ? primary : healthNSColor(.elevated)
                drawKVRow(label: "MEM", labelW: 23, value: "\(Int(renderData.memoryPercent.rounded()))%", valueW: 31, x: x, y: midY, h: rowH, labelColor: secondary, valueColor: memColor)
            }
            x += 56 + (hasMid || hasRight ? 7 : 0)
        }

        if hasMid {
            drawKVRow(label: "↑", labelW: 9, value: ByteFormatter.compactRate(renderData.uploadBytesPerSec), valueW: 36, x: x, y: topY, h: rowH, labelColor: secondary, valueColor: primary)
            drawKVRow(label: "↓", labelW: 9, value: ByteFormatter.compactRate(renderData.downloadBytesPerSec), valueW: 36, x: x, y: bottomY, h: rowH, labelColor: secondary, valueColor: primary)
            x += 47 + (hasRight ? 7 : 0)
        }

        if hasRight {
            let tempText = renderData.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "--°"
            let tempColor = renderData.temperatureCelsius.map { thermalNSColor($0, fallback: primary) } ?? secondary
            let powerText = renderData.isPowerAvailable ? String(format: "%.1fW", renderData.packageWatts) : "--W"

            if showTemperature && showPower {
                drawSingleText(tempText, in: NSRect(x: x, y: topY, width: 38, height: rowH), font: valueFont, color: tempColor, alignment: .right)
                drawSingleText(powerText, in: NSRect(x: x, y: bottomY, width: 38, height: rowH), font: valueFont, color: secondary, alignment: .right)
            } else if showTemperature {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawSingleText(tempText, in: NSRect(x: x, y: midY, width: 38, height: rowH), font: valueFont, color: tempColor, alignment: .right)
            } else if showPower {
                let midY = floor((bounds.height - rowH) / 2.0)
                drawSingleText(powerText, in: NSRect(x: x, y: midY, width: 38, height: rowH), font: valueFont, color: secondary, alignment: .right)
            }
        }
    }

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
        drawSingleText(value, in: NSRect(x: x + labelW + 2, y: y, width: valueW, height: h), font: valueFont, color: valueColor, alignment: .right)
    }

    // MARK: - 风格 B：微图表

    private func drawSparklineStyle(startX: CGFloat, bounds: NSRect, primary: NSColor, secondary: NSColor) {
        var x = startX
        let chartRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 24, height: 13)
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
        x += 24 + 5

        let cpuText = "\(Int(renderData.cpuPercent.rounded()))%"
        drawSingleText(cpuText, in: NSRect(x: x, y: 0, width: 31, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
        x += 31

        if showMemory {
            x += 6
            let capRect = NSRect(x: x, y: floor((bounds.height - 7) / 2.0), width: 22, height: 7)
            primary.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: capRect, xRadius: 2.5, yRadius: 2.5).fill()

            let ratio = min(1.0, max(0.0, renderData.memoryPercent / 100.0))
            let fillW = max(2.0, capRect.width * ratio)
            let fillRect = NSRect(x: capRect.minX, y: capRect.minY, width: fillW, height: capRect.height)
            primary.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill()
            x += 22 + 4

            let memText = "\(Int(renderData.memoryPercent.rounded()))%"
            drawSingleText(memText, in: NSRect(x: x, y: 0, width: 31, height: bounds.height), font: singleLineFont, color: secondary, alignment: .right)
        }
    }

    // MARK: - 风格 C：静默呼吸点

    private func drawBreathingDotStyle(startX: CGFloat, bounds: NSRect, primary: NSColor) {
        var x = startX
        let dotRect = NSRect(x: x, y: floor((bounds.height - 7) / 2.0), width: 7, height: 7)
        healthNSColor(renderData.healthLevel).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        x += 7 + 5

        if renderData.healthLevel == .elevated, let path = renderData.topCPUAppPath {
            let icon = AppIconCache.shared.icon(forAppPath: path)
            let iconRect = NSRect(x: x, y: floor((bounds.height - 13) / 2.0), width: 13, height: 13)
            icon.draw(in: iconRect)
            x += 13 + 4
        }

        let cpuText = "\(Int(renderData.cpuPercent.rounded()))%"
        drawSingleText(cpuText, in: NSRect(x: x, y: 0, width: 31, height: bounds.height), font: singleLineFont, color: primary, alignment: .right)
    }

    // MARK: - Helpers

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
