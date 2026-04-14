# RunCatX 🐱

> A cute menu bar runner for macOS — CPU-driven animation speed.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.0-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

**RunCatX** is a lightweight, open-source macOS menu bar application that displays an animated cat (or other creature!) whose running speed scales with your system's CPU usage. The harder your Mac works, the faster it runs!

Inspired by [Kyome22's RunCat](https://github.com/Kyome22/RunCat) and feature-complete with ideas from [RunCat365](https://github.com/Yayasyan/RunCat_for_windows).

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🐱 **5 Skins** | Cat, Dog, Frog, Snail, Bird — each with unique animations |
| ⚡ **Speed Sources** | Animation driven by **CPU** or **Memory** usage |
| 🎯 **FPS Limits** | Cap at 40 / 30 / 20 / 10 fps to save battery |
| 🌓 **Theme Support** | System / Light / Dark mode with automatic icon recoloring |
| 📊 **Live System Info** | CPU%, Memory (GB), Disk (GB) in menu |
| 🔢 **Menu Bar Text** | Optional CPU% display next to icon |
| 🚀 **Launch at Login** | Auto-start on boot (SMAppService) |
| 🔒 **Single Instance** | Flock-based guard prevents duplicate processes |
| 😴 **Sleep/Wake** | Pauses animation when display sleeps |
| ♿ **VoiceOver** | Full accessibility support with live labels |
| 💾 **Settings Persistence** | All preferences saved via UserDefaults |

## 🏗 Architecture

```
RunCatX/
├── App.swift              # Entry point, single instance, launch-at-startup, sleep/wake
├── StatusBarController.swift # NSStatusItem owner, menu, tooltip, accessibility
├── CatAnimator.swift      # Timer-driven frame animation (RunLoop.common)
├── SkinManager.swift      # Skin loading, theme recoloring (CIFilter)
├── SystemMonitor.swift    # CPU/Memory/Disk via kernel APIs
├── SettingsStore.swift    # UserDefaults persistence
└── Resources/cat/         # PNG sprite frames
```

### Design Philosophy

**Simple > Complex.** After extensive experimentation with CALayer, CVDisplayLink, and custom NSView drawing, we settled on the original RunCat's proven approach:

```swift
// Apple-optimized path — smoothest possible animation
button.image = frames[index]
RunLoop.common.add(timer, forMode: .common)
```

The interval formula matches the original exactly:

```
interval = 0.2 / clamp(usage / 5.0, 1.0, 20.0)
// → 5 fps at 0% CPU → 100 fps at 100% CPU
```

## 🛠 Building

**Prerequisites:** Xcode 15+ or Swift 6.0+, macOS 13+

```bash
# Clone & build
git clone https://github.com/krissss/RunCatX.git
cd RunCatX
swift build

# Run debug binary
.build/debug/RunCatX

# Build release
swift build -c release

# Package as .app bundle
./build-app.sh
```

### Hot-Reload Development

```bash
# Requires fswatch (brew install fswatch)
./dev.sh   # Watches *.swift → auto-builds & restarts
```

## 🎨 Skins

| Skin | Source | Frames | Style |
|------|--------|--------|-------|
| 🐱 Cat | Kyome22's original PNG sprites | 5 | Hand-drawn pixel art |
| 🐶 Dog | Programmatic Core Graphics | 16 | Geometric shapes |
| 🐸 Frog | Programmatic Core Graphics | 16 | Geometric shapes |
| 🐌 Snail | Programmatic Core Graphics | 16 | Geometric shapes |
| 🐦 Bird | Programmatic Core Graphics | 16 | Geometric shapes |

## 📸 Screenshots

*(Coming soon)*

## 🙏 Acknowledgments

- **[Kyome22/RunCat](https://github.com/Kyome22/RunCat)** — Original macOS concept & cat sprite art
- **[Yayasyan/RunCat_for_windows](https://github.com/Yayasyan/RunCat_for_windows)** — Feature inspiration (themes, FPS limits, system info)
- **[menubar_runcat](https://github.com/Kyome22/menubar_runcat)** — Reference implementation for animation architecture

## 📄 License

MIT License — see [LICENSE](LICENSE).
