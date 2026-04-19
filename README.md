# RunCatX 🐱

> A cute menu bar runner for macOS — usage-driven animation speed.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.0-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

**RunCatX** is a lightweight, open-source macOS menu bar application that displays an animated cat (or other creature!) whose running speed scales with your system usage (CPU or Memory). The harder your Mac works, the faster it runs!

Inspired by [Kyome22's RunCat](https://github.com/Kyome22/RunCat) and feature-complete with ideas from [RunCat365](https://github.com/Yayasyan/RunCat_for_windows).

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🐱 **5 Skins** | Cat, Horse, Parrot, Frog, Snail — each with unique animations |
| ⚡ **Speed Sources** | Animation driven by **CPU** or **Memory** usage |
| 🎯 **FPS Limits** | Cap at 40 / 30 / 20 / 10 fps to save battery |
| 🌓 **Theme Support** | System / Light / Dark mode with automatic icon recoloring |
| 📊 **Live System Info** | CPU%, Memory (GB), Disk (GB) in menu |
| 🔢 **Menu Bar Text** | Optional metric% (CPU/Memory) display next to icon — auto-follows speed source |
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
└── Resources/             # PNG sprite frames (cat, horse, parrot)
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
// → 5 fps at 0% usage → 100 fps at 100% usage
```

## 🛠 Building

**Prerequisites:** Xcode 16+ or Swift 6.0+, macOS 13+

```bash
git clone https://github.com/krissss/RunCatX.git
cd RunCatX
swift build -c release
```

## 🎨 Skins

| Skin | Source | Frames | Style |
|------|--------|--------|-------|
| 🐱 Cat | Kyome22's original PNG sprites | 5 | Hand-drawn pixel art |
| 🐴 Horse | RunCat365 official PNG sprites | 5 | Hand-drawn pixel art |
| 🦜 Parrot | RunCat365 official PNG sprites | 10 | Hand-drawn pixel art |
| 🐸 Frog | Programmatic Core Graphics | 16 | Geometric shapes |
| 🐌 Snail | Programmatic Core Graphics | 16 | Geometric shapes |

## 📸 Screenshots

*(Coming soon)*

## 🙏 Acknowledgments

- **[Kyome22/RunCat](https://github.com/Kyome22/RunCat)** — Original macOS concept & cat sprite art
- **[Yayasyan/RunCat_for_windows](https://github.com/Yayasyan/RunCat_for_windows)** — Feature inspiration (themes, FPS limits, system info)
- **[menubar_runcat](https://github.com/Kyome22/menubar_runcat)** — Reference implementation for animation architecture

## 📄 License

MIT License — see [LICENSE](LICENSE).
