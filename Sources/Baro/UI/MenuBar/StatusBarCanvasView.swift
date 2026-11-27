import AppKit
import BaroCore

/// 原生菜单栏精工光学渲染器：
/// - 日常状态全系支持 `isTemplate = true`（除同心光晕呼吸灯外），交由 macOS WindowServer 与 Liquid Glass
///   按底层壁纸实时反色与亚像素锐化，清晰度与系统原生 Wi-Fi / 电池图标完全一致；
/// - 含语义彩色状态（灵动圆环或高温/高负载预警）时，自动依据菜单栏外观采用 100% 纯白/纯黑高对比度渲染；
/// - 布局采用紧凑字体基准槽（Compact Reference Slot + Overflow Guard），兼顾零内部空洞与零数字抖动。
@MainActor
public enum MenuBarImageRenderer {
    // MARK: - Optical Typography

    private static let dualLabelFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
    private static let dualValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    private static let inlineValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

    // MARK: - Reference Slot Metrics (0.5pt Retina-Aligned)

    private static let outerPad: CGFloat = 3.0
    private static let pillOuterPad: CGFloat = 2.0
    private static let pillInnerPadX: CGFloat = 5.5
    private static let baroIconSize: CGFloat = 13.0
    private static let baroIconGap: CGFloat = 3.5
    private static let dividerTotalWidth: CGFloat = 8.5 // 4.0 + 0.5 hairline + 4.0

    private static let dualLabelRefW: CGFloat = measureWidth("MEM", font: dualLabelFont, kern: 0.3)
    private static let dualPctRefW: CGFloat = measureWidth("99%", font: dualValueFont)
    private static let dualRateRefW: CGFloat = measureWidth("888K", font: dualValueFont)
    private static let dualTempPowerRefW: CGFloat = measureWidth("88.8W", font: dualValueFont)

    private static let inlinePctRefW: CGFloat = measureWidth("99%", font: inlineValueFont)
    private static let inlineRateRefW: CGFloat = measureWidth("88.8M", font: inlineValueFont)
    private static let inlineTempRefW: CGFloat = measureWidth("99°", font: inlineValueFont)
    private static let inlinePowerRefW: CGFloat = measureWidth("99W", font: inlineValueFont)

    // MARK: - Render Signature (Deduplication)

    public static func renderSignature(
        data: MenuBarRenderData,
        settings: BaroSettings,
        appearance: NSAppearance
    ) -> String {
        let style = settings.menuBarStyle
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let cpuBucket = Int(data.cpuPercent.rounded())
        let memBucket = Int(data.memoryPercent.rounded())
        let upStr = settings.showMenuNetwork ? ByteFormatter.compactRate(data.uploadBytesPerSec) : ""
        let downStr = settings.showMenuNetwork ? ByteFormatter.compactRate(data.downloadBytesPerSec) : ""
        let netUpDominant = (style == .singleLine && settings.showMenuNetwork && data.uploadBytesPerSec > data.downloadBytesPerSec && data.uploadBytesPerSec > 1_024) ? "U" : "D"
        let tempBucket = settings.showMenuTemperature ? (data.temperatureCelsius.map { Int($0.rounded()) } ?? -1) : -99
        let powerStr = settings.showMenuPower ? (data.isPowerAvailable ? String(format: "%.1f", data.packageWatts) : "--") : ""
        let sparkBucket = style == .sparkline
            ? data.cpuSparklinePoints.map { String(Int($0.rounded())) }.joined(separator: ",")
            : ""
        let topApp = (style == .breathingDot && data.healthLevel == .elevated) ? (data.topCPUAppPath ?? "") : ""

        return [
            style.rawValue,
            settings.showMenuBarIcon ? "1" : "0",
            settings.showMenuCPU ? "1" : "0",
            settings.showMenuMemory ? "1" : "0",
            settings.showMenuNetwork ? "1" : "0",
            settings.showMenuTemperature ? "1" : "0",
            settings.showMenuPower ? "1" : "0",
            isDark ? "D" : "L",
            "\(cpuBucket)",
            "\(memBucket)",
            data.memoryPressure.rawValue,
            upStr,
            downStr,
            netUpDominant,
            "\(tempBucket)",
            powerStr,
            data.healthLevel.rawValue,
            topApp,
            sparkBucket
        ].joined(separator: "|")
    }

    // MARK: - Palette

    private struct RenderPalette {
        let primary: NSColor
        let secondary: NSColor
        let subtleFill: NSColor
        let subtleStroke: NSColor
        let meterFrame: NSColor
        let isTemplate: Bool
    }

    private static func makePalette(hasColorAccent: Bool, appearance: NSAppearance) -> RenderPalette {
        if hasColorAccent {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let base: NSColor = isDark ? .white : .black
            return RenderPalette(
                primary: base,
                secondary: base.withAlphaComponent(isDark ? 0.80 : 0.74),
                subtleFill: base.withAlphaComponent(isDark ? 0.11 : 0.08),
                subtleStroke: base.withAlphaComponent(isDark ? 0.26 : 0.22),
                meterFrame: base.withAlphaComponent(isDark ? 0.48 : 0.42),
                isTemplate: false
            )
        } else {
            return RenderPalette(
                primary: .black,
                secondary: NSColor.black.withAlphaComponent(0.72),
                subtleFill: NSColor.black.withAlphaComponent(0.08),
                subtleStroke: NSColor.black.withAlphaComponent(0.22),
                meterFrame: NSColor.black.withAlphaComponent(0.42),
                isTemplate: true
            )
        }
    }

    // MARK: - Main Render Entry

    public static func render(
        data: MenuBarRenderData,
        settings: BaroSettings,
        appearance: NSAppearance
    ) -> NSImage {
        let style = settings.menuBarStyle
        let showIcon = settings.showMenuBarIcon
        let showCPU = settings.showMenuCPU
        let showMemory = settings.showMenuMemory
        let showNetwork = settings.showMenuNetwork
        let showTemperature = settings.showMenuTemperature
        let showPower = settings.showMenuPower

        let hasColorAccent = needsColorRendering(
            data: data,
            style: style,
            showCPU: showCPU,
            showMemory: showMemory,
            showTemperature: showTemperature
        )
        let palette = makePalette(hasColorAccent: hasColorAccent, appearance: appearance)

        let totalWidth = computeTotalWidth(
            data: data,
            style: style,
            showIcon: showIcon,
            showCPU: showCPU,
            showMemory: showMemory,
            showNetwork: showNetwork,
            showTemperature: showTemperature,
            showPower: showPower
        )

        let size = NSSize(width: totalWidth, height: 22)
        return autoreleasepool { () -> NSImage in
            let scale: CGFloat = 2.0
            let pxW = max(1, Int(ceil(size.width * scale)))
            let pxH = max(1, Int(ceil(size.height * scale)))

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pxW,
                pixelsHigh: pxH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                return NSImage(size: size)
            }
            rep.size = size

            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                ctx.imageInterpolation = .high
                ctx.shouldAntialias = true
                let bounds = NSRect(origin: .zero, size: size)

                switch style {
                case .singleLine:
                    drawInlinePillStyle(
                        bounds: bounds,
                        data: data,
                        showIcon: showIcon,
                        showCPU: showCPU,
                        showMemory: showMemory,
                        showNetwork: showNetwork,
                        showTemperature: showTemperature,
                        showPower: showPower,
                        palette: palette
                    )
                case .compactDualRow:
                    var x = outerPad
                    if showIcon {
                        let iconRect = NSRect(x: x, y: (bounds.height - baroIconSize) * 0.5, width: baroIconSize, height: baroIconSize)
                        drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
                        x += baroIconSize + baroIconGap
                    }
                    drawDualRowPrecisionStyle(
                        startX: x,
                        bounds: bounds,
                        data: data,
                        showIcon: showIcon,
                        showCPU: showCPU,
                        showMemory: showMemory,
                        showNetwork: showNetwork,
                        showTemperature: showTemperature,
                        showPower: showPower,
                        palette: palette
                    )
                case .sparkline:
                    var x = outerPad
                    if showIcon {
                        let iconRect = NSRect(x: x, y: (bounds.height - baroIconSize) * 0.5, width: baroIconSize, height: baroIconSize)
                        drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
                        x += baroIconSize + baroIconGap
                    }
                    drawPulseGraphStyle(
                        startX: x,
                        bounds: bounds,
                        data: data,
                        showMemory: showMemory,
                        showNetwork: showNetwork,
                        palette: palette
                    )
                case .miniBars:
                    var x = outerPad
                    if showIcon {
                        let iconRect = NSRect(x: x, y: (bounds.height - baroIconSize) * 0.5, width: baroIconSize, height: baroIconSize)
                        drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
                        x += baroIconSize + baroIconGap
                    }
                    drawMicroMetersStyle(
                        startX: x,
                        bounds: bounds,
                        data: data,
                        showCPU: showCPU,
                        showMemory: showMemory,
                        showNetwork: showNetwork,
                        palette: palette
                    )
                case .breathingDot:
                    var x = outerPad
                    if showIcon {
                        let iconRect = NSRect(x: x, y: (bounds.height - baroIconSize) * 0.5, width: baroIconSize, height: baroIconSize)
                        drawBarometerSymbol(in: iconRect, loadPercent: data.cpuPercent, color: palette.primary)
                        x += baroIconSize + baroIconGap
                    }
                    drawHaloDotStyle(
                        startX: x,
                        bounds: bounds,
                        data: data,
                        showCPU: showCPU,
                        palette: palette
                    )
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            let img = NSImage(size: size)
            img.addRepresentation(rep)
            img.isTemplate = palette.isTemplate
            return img
        }
    }

    private static func needsColorRendering(
        data: MenuBarRenderData,
        style: MenuBarStyle,
        showCPU: Bool,
        showMemory: Bool,
        showTemperature: Bool
    ) -> Bool {
        switch style {
        case .breathingDot:
            return true
        case .sparkline:
            if data.cpuPercent >= 65 { return true }
            if showMemory && data.memoryPressure != .normal { return true }
            return false
        case .miniBars:
            if data.cpuPercent >= 65 { return true }
            if data.memoryPressure != .normal { return true }
            return false
        case .compactDualRow, .singleLine:
            if showCPU && data.cpuPercent >= 65 { return true }
            if showMemory && data.memoryPressure != .normal { return true }
            if showTemperature, let t = data.temperatureCelsius, t >= 75 { return true }
            return false
        }
    }

    // MARK: - Unified Exact Width Geometry

    private static func computeTotalWidth(
        data: MenuBarRenderData,
        style: MenuBarStyle,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool
    ) -> CGFloat {
        switch style {
        case .singleLine:
            let items = buildInlineTokens(
                data: data,
                showCPU: showCPU,
                showMemory: showMemory,
                showNetwork: showNetwork,
                showTemperature: showTemperature,
                showPower: showPower,
                primary: .black,
                secondary: .black
            )
            var innerW: CGFloat = pillInnerPadX * 2
            if showIcon {
                innerW += 12.0
                if !items.isEmpty {
                    innerW += 7.5 // 3.5 + hairline + 3.5
                }
            }
            if items.isEmpty {
                if !showIcon {
                    innerW += 12.0 + 3.5
                }
                innerW += measureWidth("Baro", font: inlineValueFont)
            } else {
                for (idx, item) in items.enumerated() {
                    innerW += item.slotWidth
                    if idx < items.count - 1 {
                        innerW += 6.5
                    }
                }
            }
            return ceil(pillOuterPad * 2 + innerW)

        case .compactDualRow:
            var w = outerPad * 2
            if showIcon { w += baroIconSize + baroIconGap }

            let sections = dualRowSectionWidths(
                data: data,
                showCPU: showCPU,
                showMemory: showMemory,
                showNetwork: showNetwork,
                showTemperature: showTemperature,
                showPower: showPower
            )
            if sections.isEmpty {
                if !showIcon { w += baroIconSize + 3.5 }
                w += measureWidth("Baro", font: inlineValueFont)
            } else {
                w += sections.reduce(0, +)
                if sections.count > 1 {
                    w += CGFloat(sections.count - 1) * dividerTotalWidth
                }
            }
            return ceil(w)

        case .sparkline:
            var w = outerPad * 2
            if showIcon { w += baroIconSize + baroIconGap }
            let cpuStr = "\(Int(data.cpuPercent.rounded()))%"
            let cpuW = max(inlinePctRefW, measureWidth(cpuStr, font: inlineValueFont))
            w += 28.0 + 3.5 + cpuW

            if showMemory {
                let memStr = "\(Int(data.memoryPercent.rounded()))%"
                let memW = max(inlinePctRefW, measureWidth(memStr, font: inlineValueFont))
                w += dividerTotalWidth + 11.5 + 3.0 + memW
            }
            if showNetwork {
                w += dividerTotalWidth + dualNetworkBlockWidth(data: data)
            }
            return ceil(w)

        case .miniBars:
            var w = outerPad * 2
            if showIcon { w += baroIconSize + baroIconGap }
            w += 13.5 // 5.5 + 2.5 + 5.5 twin capsule meters
            if showCPU && showMemory {
                let cStr = "\(Int(data.cpuPercent.rounded()))%"
                let mStr = "\(Int(data.memoryPercent.rounded()))%"
                let pctW = max(dualPctRefW, max(measureWidth(cStr, font: dualValueFont), measureWidth(mStr, font: dualValueFont)))
                w += 3.5 + pctW
            } else if showCPU || showMemory {
                let val = showCPU ? data.cpuPercent : data.memoryPercent
                let s = "\(Int(val.rounded()))%"
                w += 3.5 + max(inlinePctRefW, measureWidth(s, font: inlineValueFont))
            }
            if showNetwork {
                w += dividerTotalWidth + dualNetworkBlockWidth(data: data)
            }
            return ceil(w)

        case .breathingDot:
            var w = outerPad * 2
            if showIcon { w += baroIconSize + baroIconGap }
            w += 10.5
            if data.healthLevel == .elevated, data.topCPUAppPath != nil {
                w += 3.5 + 13.0
            }
            if showCPU {
                let cpuStr = "\(Int(data.cpuPercent.rounded()))%"
                w += 3.0 + max(inlinePctRefW, measureWidth(cpuStr, font: inlineValueFont))
            }
            return ceil(w)
        }
    }

    private static func dualCoreBlockWidth(data: MenuBarRenderData, showCPU: Bool, showMemory: Bool) -> CGFloat {
        if showCPU && showMemory {
            let cStr = "\(Int(data.cpuPercent.rounded()))%"
            let mStr = "\(Int(data.memoryPercent.rounded()))%"
            let valW = max(dualPctRefW, max(measureWidth(cStr, font: dualValueFont), measureWidth(mStr, font: dualValueFont)))
            return dualLabelRefW + 2.0 + valW
        } else {
            let val = showCPU ? data.cpuPercent : data.memoryPercent
            let str = "\(Int(val.rounded()))%"
            return 10.0 + 2.5 + max(inlinePctRefW, measureWidth(str, font: inlineValueFont))
        }
    }

    private static func dualNetworkBlockWidth(data: MenuBarRenderData) -> CGFloat {
        let upStr = ByteFormatter.compactRate(data.uploadBytesPerSec)
        let downStr = ByteFormatter.compactRate(data.downloadBytesPerSec)
        let rateW = max(dualRateRefW, max(measureWidth(upStr, font: dualValueFont), measureWidth(downStr, font: dualValueFont)))
        return 5.5 + 2.0 + rateW
    }

    private static func dualTempPowerBlockWidth(data: MenuBarRenderData, showTemperature: Bool, showPower: Bool) -> CGFloat {
        let tempText = data.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? "--°"
        let powerText = data.isPowerAvailable ? String(format: "%.1fW", data.packageWatts) : "--W"
        if showTemperature && showPower {
            return max(dualTempPowerRefW, max(measureWidth(tempText, font: dualValueFont), measureWidth(powerText, font: dualValueFont)))
        } else if showTemperature {
            let shortTemp = data.temperatureCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
            return 8.5 + 2.0 + max(inlineTempRefW, measureWidth(shortTemp, font: inlineValueFont))
        } else {
            let shortPower = data.isPowerAvailable ? String(format: "%.0fW", data.packageWatts) : "--W"
            return 8.5 + 2.0 + max(inlinePowerRefW, measureWidth(shortPower, font: inlineValueFont))
        }
    }

    private static func dualRowSectionWidths(
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool
    ) -> [CGFloat] {
        var widths: [CGFloat] = []
        if showCPU || showMemory {
            widths.append(dualCoreBlockWidth(data: data, showCPU: showCPU, showMemory: showMemory))
        }
        if showNetwork {
            widths.append(dualNetworkBlockWidth(data: data))
        }
        if showTemperature || showPower {
            widths.append(dualTempPowerBlockWidth(data: data, showTemperature: showTemperature, showPower: showPower))
        }
        return widths
    }

    // MARK: - Style 1: Dual-Row Precision (双行精工)

    private static func drawDualRowPrecisionStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showTemperature: Bool,
        showPower: Bool,
        palette: RenderPalette
    ) {
        var x = startX
        let hasCore = showCPU || showMemory
        let hasNet = showNetwork
        let hasTP = showTemperature || showPower

        if !hasCore && !hasNet && !hasTP {
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

    private enum MicroGlyphKind {
        case cpu
        case memory
        case netUp
        case netDown
        case temperature
        case power
    }

    private struct InlineToken {
        let kind: MicroGlyphKind
        let glyphWidth: CGFloat
        let gap: CGFloat
        let text: String
        let slotWidth: CGFloat
        let color: NSColor
    }

    private static func buildInlineTokens(
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
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

    private static func drawInlinePillStyle(
        bounds: NSRect,
        data: MenuBarRenderData,
        showIcon: Bool,
        showCPU: Bool,
        showMemory: Bool,
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
                x += 6.5
            }
        }
    }

    // MARK: - Style 3: Pulse Graph (脉搏微图)

    private static func drawPulseGraphStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showMemory: Bool,
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

        // Midline oscilloscope guide
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: strokeRect.minX + 2, y: strokeRect.midY))
        guide.line(to: NSPoint(x: strokeRect.maxX - 2, y: strokeRect.midY))
        guide.lineWidth = 0.5
        palette.subtleStroke.withAlphaComponent(0.14).setStroke()
        guide.stroke()

        let waveColor = usageNSColor(data.cpuPercent, fallback: palette.primary)
        let rawPts = data.cpuSparklinePoints.count >= 2 ? data.cpuSparklinePoints : [data.cpuPercent, data.cpuPercent]
        let padX: CGFloat = 2.0
        let padY: CGFloat = 2.0
        let plotW = viewportRect.width - padX * 2
        let plotH = viewportRect.height - padY * 2
        let stepX = plotW / CGFloat(max(1, rawPts.count - 1))

        var points: [NSPoint] = []
        points.reserveCapacity(rawPts.count)
        for (idx, val) in rawPts.enumerated() {
            let ratio = CGFloat(min(1.0, max(0.0, val / 100.0)))
            let px = viewportRect.minX + padX + CGFloat(idx) * stepX
            let py = viewportRect.minY + padY + ratio * plotH
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
            waveColor.withAlphaComponent(0.22).setFill()
            areaPath.fill()
        }

        linePath.lineWidth = 1.25
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

        if showNetwork {
            drawHairlineDivider(at: x + 4.0, bounds: bounds, color: palette.subtleStroke)
            x += dividerTotalWidth
            let netW = dualNetworkBlockWidth(data: data)
            drawDualNetworkBlock(startX: x, topY: 11.0, bottomY: 1.5, rowH: 9.5, totalW: netW, data: data, palette: palette)
        }
    }

    // MARK: - Style 4: Micro Meters (精工双柱)

    private static func drawMicroMetersStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showCPU: Bool,
        showMemory: Bool,
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

    private static func drawHaloDotStyle(
        startX: CGFloat,
        bounds: NSRect,
        data: MenuBarRenderData,
        showCPU: Bool,
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
        }
    }

    // MARK: - Precision Vector Symbols & Micro-Widgets

    private static func drawBarometerSymbol(in rect: NSRect, loadPercent: Double, color: NSColor) {
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

    private static func drawMicroGlyph(_ kind: MicroGlyphKind, in rect: NSRect, color: NSColor) {
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
                // Top & bottom pins
                pins.move(to: NSPoint(x: cx + offset, y: box.maxY))
                pins.line(to: NSPoint(x: cx + offset, y: box.maxY + 1.4))
                pins.move(to: NSPoint(x: cx + offset, y: box.minY))
                pins.line(to: NSPoint(x: cx + offset, y: box.minY - 1.4))
                // Left & right pins
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

        case .netUp:
            drawMicroArrow(in: rect, up: true, color: color)

        case .netDown:
            drawMicroArrow(in: rect, up: false, color: color)

        case .temperature:
            let bulbR: CGFloat = 2.0
            let bulbCenter = NSPoint(x: cx, y: cy - 2.2)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: bulbCenter.x - bulbR, y: bulbCenter.y - bulbR, width: bulbR * 2, height: bulbR * 2)).fill()

            let stem = NSBezierPath()
            stem.move(to: bulbCenter)
            stem.line(to: NSPoint(x: cx, y: cy + 3.8))
            stem.lineWidth = 1.8
            stem.lineCapStyle = .round
            color.setStroke()
            stem.stroke()

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

    private static func drawMicroArrow(in rect: NSRect, up: Bool, color: NSColor) {
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

    private static func drawMicroRingGauge(
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

    private static func drawDualNetworkBlock(
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
    private static func drawCenteredGlyphReadout(
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

    private static func drawHairlineDivider(
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

    private static func smoothBezierPath(through points: [NSPoint]) -> NSBezierPath {
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

    private static func measureWidth(_ string: String, font: NSFont, kern: CGFloat = 0) -> CGFloat {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if kern != 0 { attrs[.kern] = kern }
        let w = (string as NSString).size(withAttributes: attrs).width
        return ceil(w * 2.0) / 2.0
    }

    private static func drawText(
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

    private static func healthNSColor(_ level: HealthLevel) -> NSColor {
        switch level {
        case .calm: return NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.46, alpha: 1.0)
        case .moderate: return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0)
        case .elevated: return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0)
        }
    }

    private static func usageNSColor(_ percent: Double, fallback: NSColor) -> NSColor {
        if percent >= 85 { return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0) }
        if percent >= 65 { return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0) }
        return fallback
    }

    private static func thermalNSColor(_ celsius: Double, fallback: NSColor) -> NSColor {
        if celsius >= 88 { return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.26, alpha: 1.0) }
        if celsius >= 75 { return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.12, alpha: 1.0) }
        return fallback
    }
}
