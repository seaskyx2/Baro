import AppKit
import BaroCore

/// 精工矢量微图标、动态偏转晴雨表盘与排版辅助
extension MenuBarImageRenderer {
    // MARK: - Precision Vector Symbols & Micro-Widgets

    static func drawBarometerSymbol(in rect: NSRect, loadPercent: Double, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY - 0.6
        let r = rect.width * 0.43

        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: -32, endAngle: 212, clockwise: false)
        arc.lineWidth = 1.35
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()

        // Micro dial ticks at 150°, 90°, 30°
        let ticks = NSBezierPath()
        for deg in [150.0, 90.0, 30.0] {
            let rad = deg * Double.pi / 180.0
            ticks.move(to: NSPoint(x: cx + cos(rad) * (r * 0.72), y: cy + sin(rad) * (r * 0.72)))
            ticks.line(to: NSPoint(x: cx + cos(rad) * (r * 0.94), y: cy + sin(rad) * (r * 0.94)))
        }
        ticks.lineWidth = 0.85
        ticks.lineCapStyle = .round
        color.withAlphaComponent(0.50).setStroke()
        ticks.stroke()

        // Dynamic needle deflected smoothly by CPU load (148° calm -> 32° peak)
        let clamped = min(100.0, max(0.0, loadPercent))
        let needleDeg = 148.0 - (clamped / 100.0) * 116.0
        let needleRad = needleDeg * Double.pi / 180.0
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx, y: cy))
        needle.line(to: NSPoint(x: cx + cos(needleRad) * (r * 0.78), y: cy + sin(needleRad) * (r * 0.78)))
        needle.lineWidth = 1.3
        needle.lineCapStyle = .round
        color.setStroke()
        needle.stroke()

        let hubRect = NSRect(x: cx - 1.15, y: cy - 1.15, width: 2.3, height: 2.3)
        color.setFill()
        NSBezierPath(ovalIn: hubRect).fill()
    }

    static func drawMicroGlyph(_ kind: MicroGlyphKind, in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY

        switch kind {
        case .cpu:
            let box = NSRect(x: cx - 3.1, y: cy - 3.1, width: 6.2, height: 6.2)
            let p = NSBezierPath(roundedRect: box, xRadius: 1.3, yRadius: 1.3)
            p.lineWidth = 1.05
            color.setStroke()
            p.stroke()

            let core = NSRect(x: cx - 1.1, y: cy - 1.1, width: 2.2, height: 2.2)
            color.setFill()
            NSBezierPath(roundedRect: core, xRadius: 0.5, yRadius: 0.5).fill()

            let pins = NSBezierPath()
            for offset: CGFloat in [-1.4, 1.4] {
                pins.move(to: NSPoint(x: cx + offset, y: box.maxY))
                pins.line(to: NSPoint(x: cx + offset, y: box.maxY + 1.4))
                pins.move(to: NSPoint(x: cx + offset, y: box.minY))
                pins.line(to: NSPoint(x: cx + offset, y: box.minY - 1.4))
                pins.move(to: NSPoint(x: box.minX, y: cy + offset))
                pins.line(to: NSPoint(x: box.minX - 1.4, y: cy + offset))
                pins.move(to: NSPoint(x: box.maxX, y: cy + offset))
                pins.line(to: NSPoint(x: box.maxX + 1.4, y: cy + offset))
            }
            pins.lineWidth = 0.95
            pins.lineCapStyle = .round
            pins.stroke()

        case .memory:
            let chip = NSRect(x: cx - 4.2, y: cy - 2.6, width: 8.4, height: 5.2)
            let p = NSBezierPath(roundedRect: chip, xRadius: 1.2, yRadius: 1.2)
            p.lineWidth = 1.05
            color.setStroke()
            p.stroke()

            color.setFill()
            NSBezierPath(rect: NSRect(x: cx - 2.2, y: cy - 1.1, width: 1.4, height: 2.2)).fill()
            NSBezierPath(rect: NSRect(x: cx + 0.8, y: cy - 1.1, width: 1.4, height: 2.2)).fill()

            let pins = NSBezierPath()
            for offset: CGFloat in [-2.4, 0.0, 2.4] {
                pins.move(to: NSPoint(x: cx + offset, y: chip.minY))
                pins.line(to: NSPoint(x: cx + offset, y: chip.minY - 1.3))
            }
            pins.lineWidth = 0.95
            pins.lineCapStyle = .round
            pins.stroke()

        case .disk:
            let bodyRect = NSRect(x: cx - 4.3, y: cy - 3.1, width: 8.6, height: 6.2)
            let outer = NSBezierPath(roundedRect: bodyRect, xRadius: 1.4, yRadius: 1.4)
            outer.lineWidth = 1.05
            color.setStroke()
            outer.stroke()

            // Front bay separator line
            let bay = NSBezierPath()
            bay.move(to: NSPoint(x: bodyRect.minX + 0.6, y: cy - 0.7))
            bay.line(to: NSPoint(x: bodyRect.maxX - 0.6, y: cy - 0.7))
            bay.lineWidth = 0.85
            color.setStroke()
            bay.stroke()

            // Drive activity LED dot
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx + 1.8, y: cy - 2.45, width: 1.3, height: 1.3)).fill()

        case .netUp:
            drawMicroArrow(in: rect, up: true, color: color)

        case .netDown:
            drawMicroArrow(in: rect, up: false, color: color)

        case .temperature:
            let stemX = cx - 0.5
            let tubeRect = NSRect(x: stemX - 1.25, y: cy - 1.8, width: 2.5, height: 6.0)
            let tube = NSBezierPath(roundedRect: tubeRect, xRadius: 1.25, yRadius: 1.25)
            tube.lineWidth = 1.0
            color.setStroke()
            tube.stroke()

            let bulbR: CGFloat = 2.35
            let bulbCenter = NSPoint(x: stemX, y: cy - 2.3)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: bulbCenter.x - bulbR, y: bulbCenter.y - bulbR, width: bulbR * 2, height: bulbR * 2)).fill()

            let ticks = NSBezierPath()
            for ty in [cy + 0.8, cy + 2.5] {
                ticks.move(to: NSPoint(x: tubeRect.maxX + 0.8, y: ty))
                ticks.line(to: NSPoint(x: tubeRect.maxX + 2.1, y: ty))
            }
            ticks.lineWidth = 0.9
            ticks.lineCapStyle = .round
            ticks.stroke()

        case .power:
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: cx + 0.8, y: cy + 4.4))
            bolt.line(to: NSPoint(x: cx - 2.7, y: cy + 0.2))
            bolt.line(to: NSPoint(x: cx - 0.2, y: cy + 0.2))
            bolt.line(to: NSPoint(x: cx - 1.0, y: cy - 4.4))
            bolt.line(to: NSPoint(x: cx + 2.7, y: cy - 0.2))
            bolt.line(to: NSPoint(x: cx + 0.2, y: cy - 0.2))
            bolt.close()
            color.setFill()
            bolt.fill()
        }
    }

    static func drawMicroArrow(in rect: NSRect, up: Bool, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY
        let halfH: CGFloat = min(3.1, rect.height * 0.36)
        let wingW: CGFloat = 2.1

        let path = NSBezierPath()
        if up {
            let tipY = cy + halfH
            let botY = cy - halfH
            path.move(to: NSPoint(x: cx, y: botY))
            path.line(to: NSPoint(x: cx, y: tipY))
            path.move(to: NSPoint(x: cx - wingW, y: tipY - wingW))
            path.line(to: NSPoint(x: cx, y: tipY))
            path.line(to: NSPoint(x: cx + wingW, y: tipY - wingW))
        } else {
            let tipY = cy - halfH
            let topY = cy + halfH
            path.move(to: NSPoint(x: cx, y: topY))
            path.line(to: NSPoint(x: cx, y: tipY))
            path.move(to: NSPoint(x: cx - wingW, y: tipY + wingW))
            path.line(to: NSPoint(x: cx, y: tipY))
            path.line(to: NSPoint(x: cx + wingW, y: tipY + wingW))
        }
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    static func drawMicroRingGauge(
        in rect: NSRect,
        ratio: Double,
        trackColor: NSColor,
        progressColor: NSColor
    ) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = (min(rect.width, rect.height) - 1.8) * 0.5

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 1.75
        trackColor.setStroke()
        track.stroke()

        let clamped = min(1.0, max(0.03, ratio))
        let endAngle = 90.0 - clamped * 360.0
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: endAngle, clockwise: true)
        arc.lineWidth = 1.75
        arc.lineCapStyle = .round
        progressColor.setStroke()
        arc.stroke()
    }

    /// 双行精工磁盘区块：上排显示 `SSD` + 剩余容量（如 `245G`），下排显示迷你液位胶囊 + 已用百分比（如 `51%`）
    static func drawDualDiskBlock(
        startX: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        rowH: CGFloat,
        totalW: CGFloat,
        data: MenuBarRenderData,
        diskColor: NSColor,
        palette: RenderPalette
    ) {
        let freeStr = data.diskFreeBytes.map { ByteFormatter.compactDiskSize($0) } ?? "--G"
        let freeW = totalW - dualDiskLabelRefW - 2.0
        drawText("SSD", in: NSRect(x: startX, y: topY, width: dualDiskLabelRefW, height: rowH), font: dualLabelFont, color: palette.secondary, alignment: .left, kern: 0.3)
        drawText(freeStr, in: NSRect(x: startX + dualDiskLabelRefW + 2.0, y: topY, width: freeW, height: rowH), font: dualValueFont, color: diskColor, alignment: .right)

        let pctVal = data.diskUsedPercent ?? 0
        let pctStr = data.diskUsedPercent.map { "\(Int($0.rounded()))%" } ?? "--%"
        let barW: CGFloat = 16.5
        let barH: CGFloat = 3.8
        let barRect = NSRect(x: startX, y: bottomY + (rowH - barH) * 0.5, width: barW, height: barH)
        let barTrack = NSBezierPath(roundedRect: barRect.insetBy(dx: 0.35, dy: 0.35), xRadius: 1.8, yRadius: 1.8)
        palette.subtleFill.setFill()
        barTrack.fill()

        NSGraphicsContext.saveGraphicsState()
        barTrack.addClip()
        let fillRatio = CGFloat(min(1.0, max(0.08, pctVal / 100.0)))
        diskColor.setFill()
        NSBezierPath(rect: NSRect(x: barRect.minX, y: barRect.minY, width: barRect.width * fillRatio, height: barRect.height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        barTrack.lineWidth = 0.7
        palette.meterFrame.setStroke()
        barTrack.stroke()

        let pctW = totalW - barW - 2.0
        drawText(pctStr, in: NSRect(x: startX + barW + 2.0, y: bottomY, width: pctW, height: rowH), font: dualValueFont, color: diskColor == palette.primary ? palette.secondary : diskColor, alignment: .right)
    }

    static func drawDualNetworkBlock(
        startX: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        rowH: CGFloat,
        totalW: CGFloat,
        data: MenuBarRenderData,
        palette: RenderPalette
    ) {
        let arrowW: CGFloat = 5.5
        let rateW = totalW - arrowW - 2.0
        let upStr = ByteFormatter.compactRate(data.uploadBytesPerSec)
        let downStr = ByteFormatter.compactRate(data.downloadBytesPerSec)

        drawMicroArrow(in: NSRect(x: startX, y: topY, width: arrowW, height: rowH), up: true, color: palette.secondary)
        drawText(upStr, in: NSRect(x: startX + arrowW + 2.0, y: topY, width: rateW, height: rowH), font: dualValueFont, color: palette.primary, alignment: .right)

        drawMicroArrow(in: NSRect(x: startX, y: bottomY, width: arrowW, height: rowH), up: false, color: palette.secondary)
        drawText(downStr, in: NSRect(x: startX + arrowW + 2.0, y: bottomY, width: rateW, height: rowH), font: dualValueFont, color: palette.primary, alignment: .right)
    }

    /// 刚体居中稳态槽（Rigid-Unit Centered Slot）：
    /// 保证微图标与数字永远紧贴 `gap` 无空洞，同时外槽宽度恒定，避免相邻菜单栏图标抖动。
    static func drawCenteredGlyphReadout(
        kind: MicroGlyphKind,
        text: String,
        slotRect: NSRect,
        glyphWidth: CGFloat,
        gap: CGFloat,
        glyphColor: NSColor,
        textColor: NSColor
    ) {
        let actualTextW = measureWidth(text, font: inlineValueFont)
        let unitW = glyphWidth + gap + actualTextW
        let unitX = slotRect.minX + floor((slotRect.width - unitW) * 0.5 * 2.0) / 2.0

        let glyphRect = NSRect(x: unitX, y: (slotRect.height - 10.0) * 0.5, width: glyphWidth, height: 10.0)
        drawMicroGlyph(kind, in: glyphRect, color: glyphColor)

        let textRect = NSRect(x: unitX + glyphWidth + gap, y: slotRect.minY, width: actualTextW + 1.0, height: slotRect.height)
        drawText(text, in: textRect, font: inlineValueFont, color: textColor, alignment: .left)
    }

    static func drawHairlineDivider(
        at x: CGFloat,
        bounds: NSRect,
        height: CGFloat = 11.5,
        color: NSColor
    ) {
        let y0 = (bounds.height - height) * 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x + 0.25, y: y0))
        path.line(to: NSPoint(x: x + 0.25, y: y0 + height))
        path.lineWidth = 0.75
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    static func smoothBezierPath(through points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 2 {
            path.line(to: points[1])
            return path
        }
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = NSPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
            path.curve(to: mid, controlPoint1: prev, controlPoint2: prev)
        }
        if let last = points.last {
            path.line(to: last)
        }
        return path
    }

    // MARK: - Typography & Semantic Colors

    static func measureWidth(_ string: String, font: NSFont, kern: CGFloat = 0) -> CGFloat {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if kern != 0 { attrs[.kern] = kern }
        let w = (string as NSString).size(withAttributes: attrs).width
        return ceil(w * 2.0) / 2.0
    }

    static func drawText(
        _ string: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        kern: CGFloat = 0
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if kern != 0 { attrs[.kern] = kern }

        let attrStr = NSAttributedString(string: string, attributes: attrs)
        let size = attrStr.size()
        let centeredY = rect.minY + floor((rect.height - size.height) * 0.5 * 2.0) / 2.0
        attrStr.draw(in: NSRect(x: rect.minX, y: centeredY, width: rect.width, height: size.height))
    }

    static func healthNSColor(_ level: HealthLevel) -> NSColor {
        switch level {
        case .calm: return NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.46, alpha: 1.0)
        case .moderate: return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0)
        case .elevated: return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0)
        }
    }

    static func usageNSColor(_ percent: Double, fallback: NSColor) -> NSColor {
        if percent >= 85 { return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0) }
        if percent >= 65 { return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0) }
        return fallback
    }

    static func thermalNSColor(_ celsius: Double, fallback: NSColor) -> NSColor {
        if celsius >= 88 { return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0) }
        if celsius >= 75 { return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0) }
        return fallback
    }

    static func isDiskSpaceTight(freeBytes: UInt64?, usedPercent: Double?) -> Bool {
        if let free = freeBytes, free < 25_000_000_000 { return true }
        if let pct = usedPercent, pct >= 90.0 { return true }
        return false
    }

    static func diskNSColor(freeBytes: UInt64?, usedPercent: Double?, fallback: NSColor) -> NSColor {
        if let free = freeBytes, free < 12_000_000_000 {
            return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0)
        }
        if let pct = usedPercent, pct >= 95.0 {
            return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0)
        }
        if isDiskSpaceTight(freeBytes: freeBytes, usedPercent: usedPercent) {
            return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0)
        }
        return fallback
    }
}
