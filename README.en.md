# Baro

[English](README.en.md) | [简体中文](README.md)

> **Read-only vitals for macOS. Zero intrusion.**
> A lightweight, pure read-only native macOS menu bar system monitor built for Apple Silicon & macOS Liquid Glass.

## Core Philosophy

Baro (*Barometer* + *Menu Bar*) is strictly **Read-Only by Construction**:

- **Zero Control, Zero Cleanup, Zero Writes**: Never kills processes, never overrides fan curves, never deletes files, and never alters system settings.
- **Zero Background Residue**: Single-process native Swift app — no `PrivilegedHelper`, no `LaunchDaemon`, no `WidgetsExtension`. Dragging `Baro.app` to Trash removes it completely.
- **Zero Privacy Prompts**: Requests neither Location (SSID) nor Bluetooth permissions (Apple peripheral batteries are read silently via `IOKit HID`). Zero network calls, zero telemetry, zero donation popups.
- **Cold / Hot Tiered Sampling**: While collapsed, only visible menu bar metrics are lightly sampled and the hidden panel performs zero redraws; expanding the dashboard activates full hardware & per-app sampling; screen/system sleep pauses all timers automatically.
- **Native Liquid Glass Aesthetics**: Uses native `.glassEffect` on macOS 26/27 (with graceful `.ultraThinMaterial` fallback on macOS 15), Bento card layout, and `.monospacedDigit()` alignment across every readout.

## Features

- **Single-Slot Menu Bar Capsule**: 3 styles (*Compact Dual-Row*, *Sparkline*, *Breathing Dot*) that never get lost behind a display notch or reshuffle on external monitors.
- **Per-Core CPU Monitoring**: Apple Silicon P-Core vs. E-Core cluster averages, expandable per-core real-time bar chart drawer, and Load Averages.
- **Unified Memory**: Activity Monitor-aligned accounting (App, Wired, Compressed), Swap usage, and memory pressure state.
- **Apple Silicon Power, GPU & Thermals (No `sudo`)**: Reads GPU usage and energy via `libIOReport`, combined with `PowerTelemetryData` and read-only `AppleSMC` for system wattage, filtered die/zone temperatures, and fan RPM.
- **Network & Disk**: Active physical interface up/down rates, local IP, session traffic totals, deduplicated mounted volumes, and block storage throughput.
- **Adaptive Battery & Power Card**: Full battery ring gauge, charge/discharge watts, health %, cycle count, temperature, and adapter wattage on MacBooks; AC power telemetry and Apple HID peripheral batteries on desktop Macs (plus a desktop preview toggle in Preferences).
- **Parent-App Aggregated Top Processes**: Merges scattered Helper/Renderer subprocesses under their parent `.app` bundle to pinpoint CPU and memory hogs cleanly.
- **Plain-Language Health Summary**: Concise status pill summarizing system state at a glance.

## Download & Install

1. Download the latest `Baro-v*-macOS-arm64.zip` from [GitHub Releases](https://github.com/seaskyx2/Baro/releases) and unzip it.
2. Move `Baro.app` into `/Applications`.
3. Since releases are ad-hoc signed without paid Apple notarization, run this one-time command if Gatekeeper prompts on first launch:

```bash
xattr -cr /Applications/Baro.app
open /Applications/Baro.app
```

## Documentation

- [User Guide (English)](docs/USER_GUIDE.en.md) | [使用指南（简体中文）](docs/USER_GUIDE.md)
- [Product Requirements (PRD)](docs/PRD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [UI / UX Design](docs/DESIGN.md)

## Build from Source

```bash
# Run unit tests
swift test

# Run read-only CLI hardware probe
swift run Baro --probe

# Build standalone Baro.app and distributable zip (outputs to dist/)
./scripts/build_app.sh
open dist/Baro.app
```
