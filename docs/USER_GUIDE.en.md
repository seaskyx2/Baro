# Baro User Guide

[English](USER_GUIDE.en.md) | [简体中文](USER_GUIDE.md)

**Baro** (short for *Barometer* & *Menu Bar*) is a **pure read-only, zero-intrusion** native macOS system status monitor tailored for Apple Silicon (macOS 15+, with native Liquid Glass on macOS 26/27). It performs zero cleanup, zero process termination, zero fan overrides, and no network access by default (only a manual "Check for Updates" in the About window contacts GitHub).

---

## 1. Download, Installation & First Launch

1. Download the latest `Baro-v*-macOS-arm64.zip` from [GitHub Releases](https://github.com/seaskyx2/Baro/releases).
2. Unzip the archive and drag `Baro.app` into your **`/Applications`** folder.
3. **First Launch**:
   * Because Baro is an open-source, ad-hoc signed utility (without paid Apple notarization), macOS may warn about an unidentified developer when launched for the first time.
   * Run the following one-time command in Terminal to clear the download quarantine flag and open it:
     ```bash
     xattr -cr /Applications/Baro.app
     open /Applications/Baro.app
     ```
4. Once launched, Baro stays out of your Dock (`LSUIElement`) and lives cleanly in the top-right **menu bar**.

---

## 2. Menu Bar Controls & Styles

Baro occupies only **1 single menu bar slot**, preventing overlap or ordering issues on notched MacBooks:

* **Left-click** or **Global Shortcut (Default `⌃⌥B`)**: Open / close the floating dashboard panel (click outside or press `Esc` to dismiss; permission-free, customizable in Preferences).
* **Right-click**: Open the quick context menu:
  * **Open Baro Dashboard**
  * **Copy System Snapshot** (sanitized plain-text report with zero IPs or personal paths)
  * **Preferences…** (`Command + ,`)
  * **Menu Bar Style ▸** (instant 1-click switching across all 5 precision styles)
  * **Show Barometer Icon** (toggle the dynamic load-deflecting dial)
  * **User Guide** / **About Baro**
  * **Quit Baro** (`Command + Q`)

### Five Precision Menu Bar Styles
Switch anytime via the right-click menu or **Preferences → Menu Bar** (which includes a live 1:1 optical scale preview strip):

1. **Dual-Row Precision (Default)**: Hairline-divided dual-row instrument layout showing CPU, Memory, Network Up/Down, Temperature, or Power with zero dead space.
2. **Inline Pill**: Crisp vector hardware micro-glyphs framed inside a subtle rounded pill badge, ideal for external displays.
3. **Pulse Graph**: Smooth area-filled CPU waveform viewport paired with a miniature circular memory ring gauge.
4. **Micro Meters**: Native monochrome twin vertical capsule meters (turning amber/coral only under high load), ultra-compact for notched MacBooks.
5. **Halo Dot**: Concentric jewel-like halo status indicator; reveals the top CPU-consuming app icon under high load.

---

## 3. Dashboard Modules & Interactive Tips

Left-click the menu bar capsule to reveal the Bento dashboard:

### Hidden Interactive Gestures
1. **Click Cards to Expand Inline Drawers**:
   * **CPU Card**: Reveals **per-core real-time bar charts** (distinguishing Indigo `P-Cores` from Teal `E-Cores`) plus 1m/5m Load Averages.
   * **Unified Memory Card**: Expands the exact memory breakdown (App, Wired, Compressed, Cached Files, Free).
   * **Power & GPU Card**: Expands the **read-only thermal & fan sensor table** (zone temperatures and current/max RPM).
   * **Disk Card**: Expands **non-root NVMe S.M.A.R.T. health** (SSD remaining life %, total written TBW, total read, power-on hours, SSD temp) alongside secondary mounted volumes.
  * **Sanitized Snapshot Copy**: Click the copy icon in the dashboard header to copy a privacy-safe plain-text system report.
  * **Sleep Blocker Notice**: If a user app holds a sleep/display assertion, Baro gently surfaces its name in the Power card and top health summary.
   * *Click any expanded card again to collapse it.*
2. **Sparkline Hover Inspect**:
   * Glide your cursor over any sparkline chart (CPU, Memory, Power, or Network) to reveal a vertical hairline cursor and exact historical readout tooltip.

### Module Breakdown
* **Plain-Language Health Pill**: Summarizes system health at the top (e.g., *Calm · Zero swap pressure* or *High Load · Xcode using 64% CPU*).
* **CPU**: Total utilization, P/E-core cluster averages, die temperature, and 1-minute load average.
* **Unified Memory**: Matches macOS Activity Monitor accounting (`App + Wired + Compressed`), visualized via a tri-color stacked bar alongside Swap usage and kernel memory pressure level.
* **Power & GPU**: Reads Apple Silicon GPU utilization and energy via `libIOReport` without `sudo`, supplemented by `PowerTelemetryData` and read-only `AppleSMC` total system power readings.
* **Network Throughput**: Tracks live download (`↓`) / upload (`↑`) speeds across active physical interfaces, local IPv4 address, and session cumulative traffic.
* **Disk Space**: Highlights **available free space** right in the card header (turning amber/coral when below 25 GB / 12 GB), paired with used/total accounting and live I/O rates; click to expand **macOS Purgeable cache size**, external volume bars, and NVMe S.M.A.R.T. health/TBW. Disk free space can also be pinned directly in the **menu bar** with optional low-space alerts.
* **Power & Battery (Adaptive Dual-Mode)**:
  * **MacBook (Internal Battery)**: Ring charge gauge, real-time charge/discharge wattage, battery health %, cycle count, battery temperature, adapter wattage, estimated time remaining, and Apple HID peripheral battery levels.
  * **Desktop Mac (Mac mini / Mac Studio / iMac)**: Automatically switches to AC Power telemetry (live system input watts when exposed by hardware) plus Apple Magic Mouse/Keyboard/Trackpad battery levels via `IOKit HID` (no Bluetooth permission prompt). You can also toggle **"Preview Laptop Battery Card on Desktop"** in Preferences to inspect the full battery layout.
* **Top Apps (Parent-App Aggregated)**:
  * Sampled only while the panel is open. Automatically merges helper/renderer child processes into their parent `.app` bundle (with real app icons and `×N` process count badges), switchable between `[CPU | Memory]`.

---

## 4. Preferences Overview

Open Preferences via the `⚙` gear button on the dashboard or right-click menu:

* **General**: Launch at login (`SMAppService.mainApp`, requires `Baro.app` in `/Applications`), Low Power Mode interval scaling, and independent Cold (collapsed) / Hot (expanded) refresh intervals.
* **Menu Bar**: Live 1:1 optical preview strip, 5 precision display styles, dynamic barometer dial icon toggle, and individual metric toggles (2–3 metrics recommended).
* **Modules & Alerts**: Toggle any dashboard card, preview the laptop battery card on desktops, and optionally enable read-only notifications (all off by default; 10-minute cooldown) for thermal threshold, critical memory pressure, or low battery (≤ 15%).

---

## 5. Clean Uninstall (Zero Residue)

Baro installs no `LaunchDaemon`, no privileged helpers, no extensions, and writes no disk history logs. To uninstall:

1. Right-click Baro in the menu bar → **Quit Baro**.
2. Move `/Applications/Baro.app` to the Trash.

---

## 6. FAQ

* **Q: Why doesn't Baro show my Wi-Fi SSID or AirPods battery?**
  * A: Reading Wi-Fi SSIDs on modern macOS triggers a Location Services prompt, and reading AirPods battery triggers a Bluetooth permission prompt. To preserve a strict **zero-prompt, zero-intrusion** experience, Baro omits those and reads Apple HID peripherals via `IOKit` without triggering any privacy dialogs.
* **Q: Why do some M4 Macs show total system power & GPU power without per-rail CPU/ANE breakdown?**
  * A: Recent macOS versions restrict certain non-root `IOReport` energy channels on M4 hardware. Baro automatically falls back to `PowerTelemetryData` and read-only `AppleSMC` system power readings so total wattage remains accurate without elevated privileges.
* **Q: Does Baro drain power when my Mac sleeps?**
  * A: No. Baro listens to screen/system sleep notifications, pauses all sampling timers immediately upon sleep, and resets differential baselines on wake to prevent artificial spikes.
