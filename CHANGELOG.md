# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-04-24

### Added

- Initial release: animated menu bar character with speed responding to system usage
- Multiple speed sources: CPU, GPU, Memory, Disk
- Network speed monitoring (download + upload)
- Menu bar multi-metric display with color thresholds
- 6+ skins: Cat, Parrot, Horse, Mona, Dab, PartyBlobCat, Mario, Points, RunCat_U
- Pulsy virtual skin: programmatic waveform with configurable color theme, waveform style, line width, glow intensity, amplitude size
- Overview panel with real-time system metrics
- Settings window with System Settings-style NavigationSplitView
- Configurable frame rate limit (10/20/30/40 FPS)
- Configurable sample interval (0.5s ~ 10s)
- Theme adaptation (system/light/dark) with auto icon color switching
- Launch at login via SMAppService
- Single instance file lock
- Sleep pause: auto-pause animation when display sleeps
- Full VoiceOver accessibility support
- Internationalization: English + Chinese with runtime language switching
- GitHub Actions release workflow with auto Homebrew Tap update
- Custom external skin directory support

### Changed

- **Breaking**: Renamed project from RunCatX to TrayPulsy
- Replaced CPUMonitor with unified SystemMonitor
- Refactored animation engine with @Observable, Defaults.observe, enabledMetrics optimization
- Zero-allocation CPU metric collection + Core Graphics rendering
- Moved skin resources to Resources/skins directory
- Skin short labels uppercase: CPU, GPU, RAM, SSD, NET↓, NET↑

### Fixed

- Fix memory 55% baseline causing runaway animation speed
- Fix metrics not updating in Overview panel
- Fix memory calculation accuracy
- Fix settings window showing generic exec icon in Dock
- Fix empty skin FPS bug
- Fix settings window lifecycle and activation policy

## [Unreleased]

[Unreleased]: https://github.com/krissss/tray-pulsy/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/krissss/tray-pulsy/releases/tag/v1.0.0
