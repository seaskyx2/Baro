import AppKit
import BaroCore

/// 五种单槽位精工菜单栏风格的绘制实现
extension MenuBarImageRenderer {
    // MARK: - Style 1: Dual-Row Precision (双行精工)

    static func drawDualRowPrecisionStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
        showDisk: Bool,
        diskFormat: MenuBarDiskFormat,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool,
        palette: RenderPalette
    ) {
        var x = startX
        let hasCore = showCPU || showMemory
        let hasDisk = showDisk
        let hasNet = showNetwork
        let hasTP = showTemperature || showPower

        if !hasCore && !hasDisk && !hasNet && !hasTP {
            if !showIcon {
                let iconRect = NSRect(x: x, y: (bounds.height - baroIconSize) * 0.5, width: baroIconSize, height: baroIconSize)
                drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
                x += baroIconSize + 3.5
            }
            let bw = measureWidth("Baro", font: inlineValueFont)
            drawText("Baro", in: NSRect(x: x, y: 0, width: bw, height: bounds.height), font: inlineValueFont, color: palette.primary, alignment: .left)
            return
        }

        let rowH: CGFloat = 9.5
        let bottomY: CGFloat = 1.5
        let topY: CGFloat = 11.0

        if hasCore {
            let coreW = dualCoreBlockWidth(data: data, showCPU: showCPU, showMemory: showMemory)
            if showCPU && showMemory {
                let valW = coreW - dualLabelRefW - 2.0
                let cpuStr = "\(Int(data.cpuPercent.rounded()))%"
                let memStr = "\(Int(data.memoryPercent.rounded()))%"
                let cpuColor = usageNSColor(data.cpuPercent, fallback: palette.primary)
                let memColor = data.memoryPressure == .normal ? palette.primary : healthNSColor(.elevated)

                drawText("CPU", in: NSRect(x: x, y: topY, width: dualLabelRefW, height: rowH), font: dualLabelFont, color: palette.secondary, alignment: .left, kern: 0.3)
                drawText(cpuStr, in: NSRect(x: x + dualLabelRefW + 2.0, y: topY, width: valW, height: rowH), font: dualValueFont, color: cpuColor, alignment: .right)

                drawText("MEM", in: NSRect(x: x, y: bottomY, width: dualLabelRefW, height: rowH), font: dualLabelFont, color: palette.secondary, alignment: .left, kern: 0.3)
                drawText(memStr, in: NSRect(x: x + dualLabelRefW + 2.0, y: bottomY, width: valW, height: rowH), font: dualValueFont, color: memColor, alignment: .right)
            } else if showCPU {
                let cpuStr = "\(Int(data.cpuPercent.rounded()))%"
                let cpuColor = usageNSColor(data.cpuPercent, fallback: palette.primary)
                drawCenteredGlyphReadout(
                    kind: .cpu,
                    text: cpuStr,
                    slotRect: NSRect(x: x, y: 0, width: coreW, height: bounds.height),
                    glyphWidth: 10.0,
                    gap: 2.5,
                    glyphColor: palette.secondary,
                    textColor: cpuColor
                )
            } else {
                let memStr = "\(Int(data.memoryPercent.rounded()))%"
                let memColor = data.memoryPressure == .normal ? palette.primary : healthNSColor(.elevated)
                drawCenteredGlyphReadout(
                    kind: .memory,
                    text: memStr,
                    slotRect: NSRect(x: x, y: 0, width: coreW, height: bounds.height),
                    glyphWidth: 10.0,
                    gap: 2.5,
                    glyphColor: palette.secondary,
                    textColor: memColor
                )
            }
            x += coreW
            if hasDisk || hasNet || hasTP {
                drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
                x += dividerTotalWidth
            }
        }

        if hasDisk {
            let otherActive = hasCore || hasNet || hasTP
            let diskColor = diskNSColor(freeBytes: data.diskFreeBytes, usedPercent: data.diskUsedPercent, fallback: palette.primary)
            if otherActive {
                let diskW = dualDiskBlockWidth(data: data)
                drawDualDiskBlock(
                    startX: x,
                    topY: topY,
                    bottomY: bottomY,
                    rowH: rowH,
                    totalW: diskW,
                    data: data,
                    diskColor: diskColor,
                    palette: palette
                )
                x += diskW
            } else {
                let slotW = inlineDiskSlotWidth(data: data, format: diskFormat)
                let text = formatInlineDiskText(data: data, format: diskFormat)
                drawCenteredGlyphReadout(
                    kind: .disk,
                    text: text,
                    slotRect: NSRect(x: x, y: 0, width: slotW, height: bounds.height),
                    glyphWidth: 9.5,
                    gap: 2.5,
                    glyphColor: palette.secondary,
                    textColor: diskColor
                )
                x += slotW
            }

            if hasNet || hasTP {
                drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
                x += dividerTotalWidth
            }
        }

        if hasNet {
            let netW = dualNetworkBlockWidth(data: data)
            drawDualNetworkBlock(startX: x, topY: topY, bottomY: bottomY, rowH: rowH, totalW: netW, data: data, palette: palette)
            x += netW
            if hasTP {
                drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
                x += dividerTotalWidth
            }
        }

        if hasTP {
            let tpW = dualTempPowerBlockWidth(data: data, showTemperature: showTemperature, showPower: showPower)
            if showTemperature && showPower {
                let tempText = data.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "--°"
                let tempColor = data.temperatureCelsius.map { thermalNSColor($0, fallback: palette.primary) } ?? palette.secondary
                let powerText = data.isPowerAvailable ? String(format: "%.1fW", data.packageWatts) : "--W"

                drawText(tempText, in: NSRect(x: x, y: topY, width: tpW, height: rowH), font: dualValueFont, color: tempColor, alignment: .right)
                drawText(powerText, in: NSRect(x: x, y: bottomY, width: tpW, height: rowH), font: dualValueFont, color: palette.secondary, alignment: .right)
            } else if showTemperature {
                let shortTemp = data.temperatureCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
                let tempColor = data.temperatureCelsius.map { thermalNSColor($0, fallback: palette.primary) } ?? palette.secondary
                drawCenteredGlyphReadout(
                    kind: .temperature,
                    text: shortTemp,
                    slotRect: NSRect(x: x, y: 0, width: tpW, height: bounds.height),
                    glyphWidth: 8.5,
                    gap: 2.0,
                    glyphColor: palette.secondary,
                    textColor: tempColor
                )
            } else {
                let shortPower = data.isPowerAvailable ? String(format: "%.0fW", data.packageWatts) : "--W"
                drawCenteredGlyphReadout(
                    kind: .power,
                    text: shortPower,
                    slotRect: NSRect(x: x, y: 0, width: tpW, height: bounds.height),
                    glyphWidth: 8.5,
                    gap: 2.0,
                    glyphColor: palette.secondary,
                    textColor: palette.primary
                )
            }
        }
    }

    // MARK: - Style 2: Inline Pill (单行胶囊)

    static func buildInlineTokens(
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
        showDisk: Bool,
        diskFormat: MenuBarDiskFormat,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool,
        primary: NSColor,
        secondary: NSColor
    ) -> [InlineToken] {
        var list: [InlineToken] = []
        if showCPU {
            let s = "\(Int(data.cpuPercent.rounded()))%"
            let tw = max(inlinePctRefW, measureWidth(s, font: inlineValueFont))
            list.append(InlineToken(kind: .cpu, glyphWidth: 10.0, gap: 2.5, text: s, slotWidth: 10.0 + 2.5 + tw, color: usageNSColor(data.cpuPercent, fallback: primary)))
        }
        if showMemory {
            let s = "\(Int(data.memoryPercent.rounded()))%"
            let tw = max(inlinePctRefW, measureWidth(s, font: inlineValueFont))
            let c = data.memoryPressure == .normal ? primary : healthNSColor(.elevated)
            list.append(InlineToken(kind: .memory, glyphWidth: 10.0, gap: 2.5, text: s, slotWidth: 10.0 + 2.5 + tw, color: c))
        }
        if showDisk {
            let s = formatInlineDiskText(data: data, format: diskFormat)
            let slotW = inlineDiskSlotWidth(data: data, format: diskFormat)
            let c = diskNSColor(freeBytes: data.diskFreeBytes, usedPercent: data.diskUsedPercent, fallback: primary)
            list.append(InlineToken(kind: .disk, glyphWidth: 9.5, gap: 2.5, text: s, slotWidth: slotW, color: c))
        }
        if showNetwork {
            let isUp = data.uploadBytesPerSec > data.downloadBytesPerSec && data.uploadBytesPerSec > 1_024
            let rate = isUp ? ByteFormatter.compactRate(data.uploadBytesPerSec) : ByteFormatter.compactRate(data.downloadBytesPerSec)
            let tw = max(inlineRateRefW, measureWidth(rate, font: inlineValueFont))
            list.append(InlineToken(kind: isUp ? .netUp : .netDown, glyphWidth: 6.5, gap: 2.0, text: rate, slotWidth: 6.5 + 2.0 + tw, color: primary))
        }
        if showTemperature {
            let s = data.temperatureCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
            let tw = max(inlineTempRefW, measureWidth(s, font: inlineValueFont))
            let c = data.temperatureCelsius.map { thermalNSColor($0, fallback: primary) } ?? secondary
            list.append(InlineToken(kind: .temperature, glyphWidth: 8.5, gap: 2.0, text: s, slotWidth: 8.5 + 2.0 + tw, color: c))
        }
        if showPower {
            let s = data.isPowerAvailable ? String(format: "%.0fW", data.packageWatts) : "--W"
            let tw = max(inlinePowerRefW, measureWidth(s, font: inlineValueFont))
            list.append(InlineToken(kind: .power, glyphWidth: 8.5, gap: 2.0, text: s, slotWidth: 8.5 + 2.0 + tw, color: primary))
        }
        return list
    }

    static func drawInlinePillStyle(
        bounds: NSRect,
        data: MenuBarRenderData,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
        showDisk: Bool,
        diskFormat: MenuBarDiskFormat,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool,
        palette: RenderPalette
    ) {
        let pillH: CGFloat = 17.5
        let pillRect = NSRect(
            x: pillOuterPad,
            y: (bounds.height - pillH) * 0.5,
            width: bounds.width - pillOuterPad * 2,
            height: pillH
        ).insetBy(dx: 0.4, dy: 0.4)

        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 5.5, yRadius: 5.5)
        palette.subtleFill.setFill()
        pillPath.fill()
        pillPath.lineWidth = 0.75
        palette.subtleStroke.setStroke()
        pillPath.stroke()

        let tokens = buildInlineTokens(
            data: data,
            showCPU: showCPU,
            showMemory: showMemory,
            showDisk: showDisk,
            diskFormat: diskFormat,
            showNetwork: showNetwork,
            showTemperature: showTemperature,
            showPower: showPower,
            primary: palette.primary,
            secondary: palette.secondary
        )

        var x = pillOuterPad + pillInnerPadX
        if showIcon {
            let iconRect = NSRect(x: x, y: (bounds.height - 12.0) * 0.5, width: 12.0, height: 12.0)
            drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
            x += 12.0
            if !tokens.isEmpty {
                drawHairlineDivider(at: x + 3.5, bounds: bounds, height: 9.5, color: palette.subtleStroke)
                x += 7.5
            }
        }

        if tokens.isEmpty {
            if !showIcon {
                let iconRect = NSRect(x: x, y: (bounds.height - 12.0) * 0.5, width: 12.0, height: 12.0)
                drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
                x += 12.0 + 3.5
            }
            let bw = measureWidth("Baro", font: inlineValueFont)
            drawText("Baro", in: NSRect(x: x, y: 0, width: bw, height: bounds.height), font: inlineValueFont, color: palette.primary, alignment: .left)
            return
        }

        for (idx, token) in tokens.enumerated() {
            drawCenteredGlyphReadout(
                kind: token.kind,
                text: token.text,
                slotRect: NSRect(x: x, y: 0, width: token.slotWidth, height: bounds.height),
                glyphWidth: token.glyphWidth,
                gap: token.gap,
                glyphColor: palette.secondary,
                textColor: token.color
            )
            x += token.slotWidth
            if idx < tokens.count - 1 {
                x += 5.5
            }
        }
    }

    // MARK: - Style 3: Pulse Graph (脉搏微图)

    static func drawPulseGraphStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showMemory: Bool,
        showDisk: Bool,
        diskFormat: MenuBarDiskFormat,
        showNetwork: Bool,
        palette: RenderPalette
    ) {
        var x = startX
        let viewportW: CGFloat = 28.0
        let viewportH: CGFloat = 14.0
        let viewportRect = NSRect(x: x, y: (bounds.height - viewportH) * 0.5, width: viewportW, height: viewportH)
        let strokeRect = viewportRect.insetBy(dx: 0.4, dy: 0.4)
        let framePath = NSBezierPath(roundedRect: strokeRect, xRadius: 3.0, yRadius: 3.0)

        palette.subtleFill.setFill()
        framePath.fill()

        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: strokeRect.minX + 2, y: strokeRect.midY))
        guide.line(to: NSPoint(x: strokeRect.maxX - 2, y: strokeRect.midY))
        guide.lineWidth = 0.5
        palette.subtleStroke.withAlphaComponent(0.14).setStroke()
        guide.stroke()

        let waveColor = usageNSColor(data.cpuPercent, fallback: palette.primary)
        let rawPts = data.cpuSparklinePoints.count >= 2 ? data.cpuSparklinePoints : [data.cpuPercent, data.cpuPercent]
        let padX: CGFloat = 2.2
        let padBottom: CGFloat = 2.6
        let padTop: CGFloat = 2.2
        let plotW = viewportRect.width - padX * 2
        let plotH = viewportRect.height - padBottom - padTop
        let stepX = plotW / CGFloat(max(1, rawPts.count - 1))

        var points: [NSPoint] = []
        points.reserveCapacity(rawPts.count)
        for (idx, val) in rawPts.enumerated() {
            let linear = min(1.0, max(0.0, val / 100.0))
            let visualRatio = CGFloat(pow(linear, 0.82))
            let px = viewportRect.minX + padX + CGFloat(idx) * stepX
            let py = viewportRect.minY + padBottom + visualRatio * plotH
            points.append(NSPoint(x: px, y: py))
        }

        NSGraphicsContext.saveGraphicsState()
        framePath.addClip()

        let linePath = smoothBezierPath(through: points)
        if let first = points.first, let last = points.last {
            let areaPath = linePath.copy() as! NSBezierPath
            areaPath.line(to: NSPoint(x: last.x, y: viewportRect.minY))
            areaPath.line(to: NSPoint(x: first.x, y: viewportRect.minY))
            areaPath.close()
            waveColor.withAlphaComponent(0.20).setFill()
            areaPath.fill()
        }

        linePath.lineWidth = 1.4
        linePath.lineCapStyle = .round
        linePath.lineJoinStyle = .round
        waveColor.setStroke()
        linePath.stroke()

        if let last = points.last {
            let dotRect = NSRect(x: last.x - 1.15, y: last.y - 1.15, width: 2.3, height: 2.3)
            waveColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        framePath.lineWidth = 0.75
        palette.subtleStroke.setStroke()
        framePath.stroke()

        x += viewportW + 3.5

        let cpuStr = "\(Int(data.cpuPercent.rounded()))%"
        let cpuW = max(inlinePctRefW, measureWidth(cpuStr, font: inlineValueFont))
        drawText(cpuStr, in: NSRect(x: x, y: 0, width: cpuW, height: bounds.height), font: inlineValueFont, color: waveColor, alignment: .right)
        x += cpuW

        if showMemory {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth

            let ringSize: CGFloat = 11.5
            let ringRect = NSRect(x: x, y: (bounds.height - ringSize) * 0.5, width: ringSize, height: ringSize)
            let memColor = data.memoryPressure == .normal ? palette.primary : healthNSColor(.elevated)
            drawMicroRingGauge(in: ringRect, ratio: data.memoryPercent / 100.0, trackColor: palette.subtleStroke, progressColor: memColor)
            x += ringSize + 3.0

            let memStr = "\(Int(data.memoryPercent.rounded()))%"
            let memW = max(inlinePctRefW, measureWidth(memStr, font: inlineValueFont))
            drawText(memStr, in: NSRect(x: x, y: 0, width: memW, height: bounds.height), font: inlineValueFont, color: memColor, alignment: .right)
            x += memW
        }

        if showDisk {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth
            let slotW = inlineDiskSlotWidth(data: data, format: diskFormat)
            let text = formatInlineDiskText(data: data, format: diskFormat)
            let diskColor = diskNSColor(freeBytes: data.diskFreeBytes, usedPercent: data.diskUsedPercent, fallback: palette.primary)
            drawCenteredGlyphReadout(
                kind: .disk,
                text: text,
                slotRect: NSRect(x: x, y: 0, width: slotW, height: bounds.height),
                glyphWidth: 9.5,
                gap: 2.5,
                glyphColor: palette.secondary,
                textColor: diskColor
            )
            x += slotW
        }

        if showNetwork {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth
            let netW = dualNetworkBlockWidth(data: data)
            drawDualNetworkBlock(startX: x, topY: 11.0, bottomY: 1.5, rowH: 9.5, totalW: netW, data: data, palette: palette)
        }
    }

    // MARK: - Style 4: Micro Meters (精工双柱)

    static func drawMicroMetersStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
        showDisk: Bool,
        diskFormat: MenuBarDiskFormat,
        showNetwork: Bool,
        palette: RenderPalette
    ) {
        var x = startX
        let meterW: CGFloat = 5.5
        let meterH: CGFloat = 14.5
        let meterY = (bounds.height - meterH) * 0.5

        let cpuColor = usageNSColor(data.cpuPercent, fallback: palette.primary)
        let memColor = data.memoryPressure == .normal ? palette.primary : healthNSColor(.elevated)

        drawPrecisionCapsuleMeter(
            in: NSRect(x: x, y: meterY, width: meterW, height: meterH),
            ratio: data.cpuPercent / 100.0,
            fillColor: cpuColor,
            palette: palette
        )
        drawPrecisionCapsuleMeter(
            in: NSRect(x: x + meterW + 2.5, y: meterY, width: meterW, height: meterH),
            ratio: data.memoryPercent / 100.0,
            fillColor: memColor,
            palette: palette
        )
        x += 13.5

        if showCPU && showMemory {
            x += 3.5
            let cStr = "\(Int(data.cpuPercent.rounded()))%"
            let mStr = "\(Int(data.memoryPercent.rounded()))%"
            let pctW = max(dualPctRefW, max(measureWidth(cStr, font: dualValueFont), measureWidth(mStr, font: dualValueFont)))
            drawText(cStr, in: NSRect(x: x, y: 11.0, width: pctW, height: 9.5), font: dualValueFont, color: cpuColor, alignment: .right)
            drawText(mStr, in: NSRect(x: x, y: 1.5, width: pctW, height: 9.5), font: dualValueFont, color: memColor == palette.primary ? palette.secondary : memColor, alignment: .right)
            x += pctW
        } else if showCPU || showMemory {
            x += 3.5
            let val = showCPU ? data.cpuPercent : data.memoryPercent
            let color = showCPU ? cpuColor : memColor
            let str = "\(Int(val.rounded()))%"
            let pctW = max(inlinePctRefW, measureWidth(str, font: inlineValueFont))
            drawText(str, in: NSRect(x: x, y: 0, width: pctW, height: bounds.height), font: inlineValueFont, color: color, alignment: .right)
            x += pctW
        }

        if showDisk {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth
            let slotW = inlineDiskSlotWidth(data: data, format: diskFormat)
            let text = formatInlineDiskText(data: data, format: diskFormat)
            let diskColor = diskNSColor(freeBytes: data.diskFreeBytes, usedPercent: data.diskUsedPercent, fallback: palette.primary)
            drawCenteredGlyphReadout(
                kind: .disk,
                text: text,
                slotRect: NSRect(x: x, y: 0, width: slotW, height: bounds.height),
                glyphWidth: 9.5,
                gap: 2.5,
                glyphColor: palette.secondary,
                textColor: diskColor
            )
            x += slotW
        }

        if showNetwork {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth
            let netW = dualNetworkBlockWidth(data: data)
            drawDualNetworkBlock(startX: x, topY: 11.0, bottomY: 1.5, rowH: 9.5, totalW: netW, data: data, palette: palette)
        }
    }

    private static func drawPrecisionCapsuleMeter(
        in rect: NSRect,
        ratio: Double,
        fillColor: NSColor,
        palette: RenderPalette
    ) {
        let strokeRect = rect.insetBy(dx: 0.42, dy: 0.42)
        let outerPath = NSBezierPath(roundedRect: strokeRect, xRadius: 2.1, yRadius: 2.1)
        palette.subtleFill.setFill()
        outerPath.fill()

        NSGraphicsContext.saveGraphicsState()
        outerPath.addClip()
        let clamped = CGFloat(min(1.0, max(0.0, ratio)))
        let fillH = max(2.2, rect.height * clamped)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fillH)
        fillColor.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        outerPath.lineWidth = 0.85
        palette.meterFrame.setStroke()
        outerPath.stroke()
    }

    // MARK: - Style 5: Halo Dot (灵动圆环)

    static func drawHaloDotStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showCPU: Bool,
        showDisk: Bool,
        diskFormat: MenuBarDiskFormat,
        palette: RenderPalette
    ) {
        var x = startX
        let haloSize: CGFloat = 10.5
        let haloRect = NSRect(x: x, y: (bounds.height - haloSize) * 0.5, width: haloSize, height: haloSize)
        let statusColor = healthNSColor(data.healthLevel)

        let ringRect = haloRect.insetBy(dx: 0.5, dy: 0.5)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        statusColor.withAlphaComponent(0.18).setFill()
        ringPath.fill()
        ringPath.lineWidth = 0.95
        statusColor.withAlphaComponent(0.52).setStroke()
        ringPath.stroke()

        let coreSize: CGFloat = 4.8
        let coreRect = NSRect(x: haloRect.midX - coreSize * 0.5, y: haloRect.midY - coreSize * 0.5, width: coreSize, height: coreSize)
        statusColor.setFill()
        NSBezierPath(ovalIn: coreRect).fill()

        x += haloSize

        if data.healthLevel == .elevated, let path = data.topCPUAppPath {
            x += 3.5
            let icon = AppIconCache.shared.icon(forAppPath: path)
            let iconRect = NSRect(x: x, y: (bounds.height - 13.0) * 0.5, width: 13.0, height: 13.0)
            icon.draw(in: iconRect)
            x += 13.0
        }

        if showCPU {
            x += 3.0
            let cpuStr = "\(Int(data.cpuPercent.rounded()))%"
            let cpuW = max(inlinePctRefW, measureWidth(cpuStr, font: inlineValueFont))
            drawText(cpuStr, in: NSRect(x: x, y: 0, width: cpuW, height: bounds.height), font: inlineValueFont, color: palette.primary, alignment: .right)
            x += cpuW
        }

        if showDisk {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth
            let slotW = inlineDiskSlotWidth(data: data, format: diskFormat)
            let text = formatInlineDiskText(data: data, format: diskFormat)
            let diskColor = diskNSColor(freeBytes: data.diskFreeBytes, usedPercent: data.diskUsedPercent, fallback: palette.primary)
            drawCenteredGlyphReadout(
                kind: .disk,
                text: text,
                slotRect: NSRect(x: x, y: 0, width: slotW, height: bounds.height),
                glyphWidth: 9.5,
                gap: 2.5,
                glyphColor: palette.secondary,
                textColor: diskColor
            )
        }
    }
}
