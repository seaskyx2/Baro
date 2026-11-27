import AppKit
import BaroCore

/// 原生菜单栏精工光学渲染器（入口、签名与精确几何宽度）：
/// - 日常状态全系支持 `isTemplate = true`（除同心光晕呼吸灯外），交由 macOS WindowServer 与 Liquid Glass
///   按底层壁纸实时反色与亚像素锐化，清晰度与系统原生 Wi-Fi / 电池图标完全一致；
/// - 含语义彩色状态（灵动圆环或高温/高负载预警）时，自动依据菜单栏外观采用 100% 纯白/纯黑高对比度渲染；
/// - 布局采用紧凑字体基准槽（Compact Reference Slot + Overflow Guard），兼顾零内部空洞与零数字抖动。
@MainActor
public enum MenuBarImageRenderer {
    // MARK: - Optical Typography

    static let dualLabelFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
    static let dualValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    static let inlineValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

    // MARK: - Reference Slot Metrics (0.5pt Retina-Aligned)

    static let outerPad: CGFloat = 3.0
    static let pillOuterPad: CGFloat = 2.0
    static let pillInnerPadX: CGFloat = 5.5
    static let baroIconSize: CGFloat = 13.0
    static let baroIconGap: CGFloat = 3.5
    static let dividerTotalWidth: CGFloat = 8.5 // 4.0 + 0.5 hairline + 4.0

    static let dualLabelRefW: CGFloat = measureWidth("MEM", font: dualLabelFont, kern: 0.3)
    static let dualPctRefW: CGFloat = measureWidth("99%", font: dualValueFont)
    static let dualRateRefW: CGFloat = measureWidth("888K", font: dualValueFont)
    static let dualTempPowerRefW: CGFloat = measureWidth("88.8W", font: dualValueFont)

    static let inlinePctRefW: CGFloat = measureWidth("99%", font: inlineValueFont)
    static let inlineRateRefW: CGFloat = measureWidth("888K", font: inlineValueFont)
    static let inlineTempRefW: CGFloat = measureWidth("99°", font: inlineValueFont)
    static let inlinePowerRefW: CGFloat = measureWidth("99W", font: inlineValueFont)

    // MARK: - Shared Types

    struct RenderPalette {
        let primary: NSColor
        let secondary: NSColor
        let subtleFill: NSColor
        let subtleStroke: NSColor
        let meterFrame: NSColor
        let isTemplate: Bool
    }

    enum MicroGlyphKind {
        case cpu
        case memory
        case netUp
        case netDown
        case temperature
        case power
    }

    struct InlineToken {
        let kind: MicroGlyphKind
        let glyphWidth: CGFloat
        let gap: CGFloat
        let text: String
        let slotWidth: CGFloat
        let color: NSColor
    }

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

    static func makePalette(hasColorAccent: Bool, appearance: NSAppearance) -> RenderPalette {
        if hasColorAccent {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let base: NSColor = isDark ? .white : .black
            return RenderPalette(
                primary: base,
                secondary: base.withAlphaComponent(isDark ? 0.80 : 0.74),
                subtleFill: base.withAlphaComponent(isDark ? 0.08 : 0.06),
                subtleStroke: base.withAlphaComponent(isDark ? 0.26 : 0.22),
                meterFrame: base.withAlphaComponent(isDark ? 0.48 : 0.42),
                isTemplate: false
            )
        } else {
            return RenderPalette(
                primary: .black,
                secondary: NSColor.black.withAlphaComponent(0.72),
                subtleFill: NSColor.black.withAlphaComponent(0.05),
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

    static func needsColorRendering(
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

    public static func computeTotalWidth(
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
                        innerW += 5.5
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

    static func dualCoreBlockWidth(data: MenuBarRenderData, showCPU: Bool, showMemory: Bool) -> CGFloat {
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

    static func dualNetworkBlockWidth(data: MenuBarRenderData) -> CGFloat {
        let upStr = ByteFormatter.compactRate(data.uploadBytesPerSec)
        let downStr = ByteFormatter.compactRate(data.downloadBytesPerSec)
        let rateW = max(dualRateRefW, max(measureWidth(upStr, font: dualValueFont), measureWidth(downStr, font: dualValueFont)))
        return 5.5 + 2.0 + rateW
    }

    static func dualTempPowerBlockWidth(data: MenuBarRenderData, showTemperature: Bool, showPower: Bool) -> CGFloat {
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

    static func dualRowSectionWidths(
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
}
