import Defaults
import Foundation

/// Lightweight localization helper with runtime language switching.
/// Translations are compiled into the binary for maximum reliability
/// across all build environments (Xcode, swift run, make app).
///
/// To add/update translations: edit the `tables` dictionary below.
enum L10n {

    // MARK: - Core

    static let languageDidChangeNotification = Notification.Name("L10n.languageDidChange")

    private static let _lock = NSLock()
    private nonisolated(unsafe) static var _strings: [String: String] = loadTable()

    private static func loadTable() -> [String: String] {
        let lang = currentLanguage()
        return tables[lang] ?? tables["en"] ?? [:]
    }

    private static func currentLanguage() -> String {
        let saved = Defaults[.language]
        switch saved {
        case .en:     return "en"
        case .zhHans: return "zh-Hans"
        case .system: break
        }
        return Locale.current.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
    }

    static func tr(_ key: String, _ defaultValue: String) -> String {
        _lock.lock()
        defer { _lock.unlock() }
        return _strings[key] ?? defaultValue
    }

    /// Reload strings (call after language change).
    static func reload() {
        let newTable = loadTable()
        _lock.lock()
        _strings = newTable
        _lock.unlock()
        NotificationCenter.default.post(name: languageDidChangeNotification, object: nil)
    }

    // MARK: - Translation Tables

    private static let tables: [String: [String: String]] = [
        "en": [
            // Tab Labels
            "tab.overview": "Overview",
            "tab.skin": "Skins",
            "tab.metrics": "Metrics",
            "tab.performance": "Performance",
            "tab.general": "General",
            "tab.about": "About",

            // Speed Source
            "speed.cpu": "CPU",
            "speed.gpu": "GPU",
            "speed.memory": "Memory",
            "speed.disk": "Disk",

            // Metric Display Items
            "metric.cpu": "CPU Usage",
            "metric.gpu": "GPU Usage",
            "metric.memory": "Memory",
            "metric.disk": "Disk",
            "metric.netDown": "Download Speed",
            "metric.netUp": "Upload Speed",

            "metric.overview.cpu": "CPU",
            "metric.overview.gpu": "GPU",
            "metric.overview.memory": "Memory",
            "metric.overview.disk": "Disk",
            "metric.overview.down": "Down",
            "metric.overview.up": "Up",

            // FPS Limit
            "fps.10": "10 FPS",
            "fps.20": "20 FPS",
            "fps.30": "30 FPS",
            "fps.40": "40 FPS",

            // Sample Interval
            "interval.0.5": "0.5 sec",
            "interval.1": "1 sec",
            "interval.2": "2 sec",
            "interval.3": "3 sec",
            "interval.5": "5 sec",
            "interval.10": "10 sec",

            // Theme Mode
            "theme.system": "System",
            "theme.light": "Light",
            "theme.dark": "Dark",

            // Overview
            "overview.monitorHeader": "System Monitor",
            "overview.activityMonitor": "Activity Monitor",
            "overview.network": "Network",
            "overview.processHeader": "Processes",

            // Skin Settings
            "settings.skin.header": "Skins",
            "settings.skin.libraryHeader": "Skin Library",
            "settings.skin.pathLabel": "Path",
            "settings.skin.pathPrompt": "~/skins",
            "settings.skin.browse": "Browse",
            "settings.skin.extHeader": "External Skins",
            "settings.skin.extInfo": "Each subfolder is one skin containing PNG frame sequences.\nFolder name = skin name (e.g. 01.cat → cat). Same name overrides built-in skins.",
            "settings.skin.pathNotFound": "Path not found",

            // Metrics Settings
            "settings.metrics.header": "Menu Bar Metrics",
            "settings.metrics.footer": "Select metrics to display next to the menu bar icon. Drag the sliders to set color thresholds.",

            // Performance Settings
            "performance.source.label": "Animation Drive",
            "performance.source.header": "Speed Source",
            "performance.source.footer": "Animation speed follows the selected metric in real time.",
            "performance.fps.label": "Max Frame Rate",
            "performance.fps.header": "Frame Rate Control",
            "performance.fps.footer": "Limit max frame rate to reduce CPU usage.",
            "performance.sample.label": "Sample Interval",
            "performance.sample.header": "Data Sampling",
            "performance.sample.footer": "Shorter intervals make animation more responsive but slightly increase CPU usage.",

            // History Duration
            "performance.history.label": "History Duration",
            "performance.history.header": "Chart History",
            "performance.history.footer": "Time range shown in trend charts. Longer durations use more memory.",
            "historyDuration.5": "5 min",
            "historyDuration.10": "10 min",
            "historyDuration.15": "15 min",
            "historyDuration.30": "30 min",
            "historyDuration.60": "60 min",

            // General Settings
            "general.startup.header": "Startup",
            "general.startup.toggle": "Launch at Login",
            "general.startup.footer": "Automatically launch %@ in the menu bar at login.",
            "general.language.header": "Language",
            "general.language.system": "System",

            // About
            "about.info.header": "Info",
            "about.developer": "Developer",
            "about.inspiration": "Inspiration",
            "about.quit": "Quit %@",
            "about.version": "Version %@",

            // Accessibility
            "acc.skinPreview": "Current skin preview",
            "acc.selected": ", selected",
            "acc.clickToOpen": ", click to open settings",

            // Pulsy Color Theme
            "pulsy.color.fire": "Fire",
            "pulsy.color.ocean": "Ocean",
            "pulsy.color.matrix": "Matrix",
            "pulsy.color.neon": "Neon",
            "pulsy.color.monochrome": "Monochrome",

            // Pulsy Waveform Style
            "pulsy.wave.ecg": "ECG",
            "pulsy.wave.sine": "Sine",
            "pulsy.wave.sawtooth": "Sawtooth",
            "pulsy.wave.square": "Square",
            "pulsy.wave.spike": "Spike",

            // Pulsy Settings
            "pulsy.settings.header": "Pulsy Controls",
            "pulsy.settings.colorTheme": "Color Theme",
            "pulsy.settings.waveform": "Waveform Style",
            "pulsy.settings.lineWidth": "Line Width",
            "pulsy.settings.glowIntensity": "Glow Intensity",
            "pulsy.settings.amplitudeSensitivity": "Amplitude Size",
            "pulsy.settings.calm": "Calm",
            "pulsy.settings.intense": "Intense",

            // Window
            "window.title": "Settings",

            // Popover
            "popover.historyFooter": "30-min history",
            "popover.metric.cpu": "CPU",
            "popover.metric.ram": "RAM",
            "popover.metric.ssd": "SSD",
            "popover.metric.net": "NET",
            "popover.metric.gpu": "GPU",
            "popover.openMainWindow": "Open Main Window",
            "popover.process.topProcesses": "Top Processes",
            "popover.process.sampling": "Sampling process activity...",
            "popover.process.noActivity": "No active processes",
            "popover.process.showCPU": "Show CPU processes",
            "popover.process.showMemory": "Show memory processes",
            "popover.process.cpuHeader": "% CPU",
            "popover.process.memoryHeader": "Memory / %",
            "popover.network.topProcesses": "Top Processes",
            "popover.network.processHeader": "Down / Up",
            "popover.network.toggle": "Show network processes",
            "popover.network.download": "download",
            "popover.network.upload": "upload",
            "popover.network.sortHelp": "Sort by %@",
            "popover.network.sort.activity": "Activity",
            "popover.network.sort.download": "Download",
            "popover.network.sort.upload": "Upload",
            "popover.network.sort.total": "Total",
            "popover.network.sort.activityShort": "Active",
            "popover.network.sort.downloadShort": "Down",
            "popover.network.sort.uploadShort": "Up",
            "popover.network.sort.totalShort": "Total",
            "popover.quit": "Quit",

            // Update
            "update.autoCheck.header": "Updates",
            "update.autoCheck.toggle": "Check for Updates Automatically",
            "update.autoCheck.footer": "Click to check for new versions of %@.",
            "update.checkNow": "Check for Updates",
            "update.error.debug": "Update check is not available in debug mode.",
            "update.interval.header": "Check Frequency",
            "update.interval.daily": "Daily",
            "update.interval.weekly": "Weekly",
            "update.interval.monthly": "Monthly",
            "update.autoDownload.toggle": "Automatically download updates",
            "update.lastChecked": "Last checked: %@",
            "update.neverChecked": "Never",
        ],

        "zh-Hans": [
            // Tab Labels
            "tab.overview": "概览",
            "tab.skin": "皮肤",
            "tab.metrics": "指标",
            "tab.performance": "性能",
            "tab.general": "通用",
            "tab.about": "关于",

            // Speed Source
            "speed.cpu": "CPU",
            "speed.gpu": "GPU",
            "speed.memory": "内存",
            "speed.disk": "磁盘",

            // Metric Display Items
            "metric.cpu": "CPU 使用率",
            "metric.gpu": "GPU 使用率",
            "metric.memory": "内存",
            "metric.disk": "磁盘",
            "metric.netDown": "下行网速",
            "metric.netUp": "上行网速",

            "metric.overview.cpu": "CPU",
            "metric.overview.gpu": "GPU",
            "metric.overview.memory": "内存",
            "metric.overview.disk": "磁盘",
            "metric.overview.down": "下行",
            "metric.overview.up": "上行",

            // FPS Limit
            "fps.10": "10 FPS",
            "fps.20": "20 FPS",
            "fps.30": "30 FPS",
            "fps.40": "40 FPS",

            // Sample Interval
            "interval.0.5": "0.5 秒",
            "interval.1": "1 秒",
            "interval.2": "2 秒",
            "interval.3": "3 秒",
            "interval.5": "5 秒",
            "interval.10": "10 秒",

            // Theme Mode
            "theme.system": "跟随系统",
            "theme.light": "浅色",
            "theme.dark": "深色",

            // Overview
            "overview.monitorHeader": "系统监控",
            "overview.activityMonitor": "活动监视器",
            "overview.network": "网络",
            "overview.processHeader": "进程",

            // Skin Settings
            "settings.skin.header": "皮肤",
            "settings.skin.libraryHeader": "皮肤库",
            "settings.skin.pathLabel": "路径",
            "settings.skin.pathPrompt": "~/skins",
            "settings.skin.browse": "浏览",
            "settings.skin.extHeader": "外部皮肤",
            "settings.skin.extInfo": "每个子文件夹为一个皮肤，内含 PNG 序列帧。\n文件夹名即皮肤名（如 01.cat → cat），同名会覆盖内置皮肤。",
            "settings.skin.pathNotFound": "路径不存在",

            // Metrics Settings
            "settings.metrics.header": "菜单栏指标",
            "settings.metrics.footer": "勾选要在菜单栏图标旁显示的指标，拖动滑块设置颜色阈值。",

            // Performance Settings
            "performance.source.label": "动画驱动",
            "performance.source.header": "速度来源",
            "performance.source.footer": "动画速度将跟随所选指标实时变化。",
            "performance.fps.label": "最高帧率",
            "performance.fps.header": "帧率控制",
            "performance.fps.footer": "限制最高帧率以降低 CPU 占用。",
            "performance.sample.label": "采样频率",
            "performance.sample.header": "数据采样",
            "performance.sample.footer": "间隔越短，动画响应越快，但 CPU 占用略高。",

            // History Duration
            "performance.history.label": "历史时长",
            "performance.history.header": "趋势图历史",
            "performance.history.footer": "趋势图显示的时间范围。时长越长占用更多内存。",
            "historyDuration.5": "5 分钟",
            "historyDuration.10": "10 分钟",
            "historyDuration.15": "15 分钟",
            "historyDuration.30": "30 分钟",
            "historyDuration.60": "60 分钟",

            // General Settings
            "general.startup.header": "启动",
            "general.startup.toggle": "开机自动启动",
            "general.startup.footer": "登录时自动在菜单栏启动 %@。",
            "general.language.header": "语言",
            "general.language.system": "跟随系统",

            // About
            "about.info.header": "信息",
            "about.developer": "开发者",
            "about.inspiration": "灵感来源",
            "about.quit": "退出 %@",
            "about.version": "版本 %@",

            // Accessibility
            "acc.skinPreview": "当前皮肤预览",
            "acc.selected": "，已选中",
            "acc.clickToOpen": "，点击打开设置",

            // Window
            "window.title": "设置",

            // Popover
            "popover.historyFooter": "30 分钟历史",
            "popover.metric.cpu": "CPU",
            "popover.metric.ram": "内存",
            "popover.metric.ssd": "硬盘",
            "popover.metric.net": "网络",
            "popover.metric.gpu": "GPU",
            "popover.openMainWindow": "打开主界面",
            "popover.process.topProcesses": "进程排行",
            "popover.process.sampling": "正在采样进程活动...",
            "popover.process.noActivity": "暂无活跃进程",
            "popover.process.showCPU": "显示 CPU 进程",
            "popover.process.showMemory": "显示内存进程",
            "popover.process.cpuHeader": "% CPU",
            "popover.process.memoryHeader": "内存 / %",
            "popover.network.topProcesses": "进程排行",
            "popover.network.processHeader": "下行 / 上行",
            "popover.network.toggle": "显示网络进程",
            "popover.network.download": "下行",
            "popover.network.upload": "上行",
            "popover.network.sortHelp": "按%@排序",
            "popover.network.sort.activity": "活跃度",
            "popover.network.sort.download": "下行",
            "popover.network.sort.upload": "上行",
            "popover.network.sort.total": "总量",
            "popover.network.sort.activityShort": "活跃",
            "popover.network.sort.downloadShort": "下行",
            "popover.network.sort.uploadShort": "上行",
            "popover.network.sort.totalShort": "总量",
            "popover.quit": "退出",

            // Update
            "update.autoCheck.header": "更新",
            "update.autoCheck.toggle": "自动检查更新",
            "update.checkNow": "检查更新",
            "update.error.debug": "调试模式下不支持检查更新。",
            "update.interval.header": "检查频率",
            "update.interval.daily": "每天",
            "update.interval.weekly": "每周",
            "update.interval.monthly": "每月",
            "update.autoDownload.toggle": "自动下载更新",
            "update.lastChecked": "上次检查：%@",
            "update.neverChecked": "从未",

            // Pulsy Color Theme
            "pulsy.color.fire": "火焰",
            "pulsy.color.ocean": "海洋",
            "pulsy.color.matrix": "矩阵",
            "pulsy.color.neon": "霓虹",
            "pulsy.color.monochrome": "黑白",

            // Pulsy Waveform Style
            "pulsy.wave.ecg": "心电图",
            "pulsy.wave.sine": "正弦波",
            "pulsy.wave.sawtooth": "锯齿波",
            "pulsy.wave.square": "方波",
            "pulsy.wave.spike": "尖峰",

            // Pulsy Settings
            "pulsy.settings.header": "Pulsy 控制台",
            "pulsy.settings.colorTheme": "配色主题",
            "pulsy.settings.waveform": "波形样式",
            "pulsy.settings.lineWidth": "线条粗细",
            "pulsy.settings.glowIntensity": "发光强度",
            "pulsy.settings.amplitudeSensitivity": "振幅大小",
            "pulsy.settings.calm": "平静",
            "pulsy.settings.intense": "激烈",
        ],
    ]

    // MARK: - Tab Labels

    static var tabOverview:    String { tr("tab.overview", "概览") }
    static var tabSkin:        String { tr("tab.skin", "皮肤") }
    static var tabMetrics:     String { tr("tab.metrics", "指标") }
    static var tabPerformance: String { tr("tab.performance", "性能") }
    static var tabGeneral:     String { tr("tab.general", "通用") }
    static var tabAbout:       String { tr("tab.about", "关于") }

    // MARK: - Speed Source

    static var speedCpu:    String { tr("speed.cpu", "CPU") }
    static var speedGpu:    String { tr("speed.gpu", "GPU") }
    static var speedMemory: String { tr("speed.memory", "内存") }
    static var speedDisk:   String { tr("speed.disk", "磁盘") }

    // MARK: - Metric Display Items

    static var metricCpu:       String { tr("metric.cpu", "CPU 使用率") }
    static var metricGpu:       String { tr("metric.gpu", "GPU 使用率") }
    static var metricMemory:    String { tr("metric.memory", "内存") }
    static var metricDisk:      String { tr("metric.disk", "磁盘") }
    static var metricNetDown:   String { tr("metric.netDown", "下行网速") }
    static var metricNetUp:     String { tr("metric.netUp", "上行网速") }

    static var metricOverviewCpu:    String { tr("metric.overview.cpu", "CPU") }
    static var metricOverviewGpu:    String { tr("metric.overview.gpu", "GPU") }
    static var metricOverviewMemory: String { tr("metric.overview.memory", "内存") }
    static var metricOverviewDisk:   String { tr("metric.overview.disk", "磁盘") }

    // MARK: - FPS Limit

    static var fps10: String { tr("fps.10", "10 FPS") }
    static var fps20: String { tr("fps.20", "20 FPS") }
    static var fps30: String { tr("fps.30", "30 FPS") }
    static var fps40: String { tr("fps.40", "40 FPS") }

    // MARK: - Sample Interval

    static var interval05:  String { tr("interval.0.5", "0.5 秒") }
    static var interval1:   String { tr("interval.1", "1 秒") }
    static var interval2:   String { tr("interval.2", "2 秒") }
    static var interval3:   String { tr("interval.3", "3 秒") }
    static var interval5:   String { tr("interval.5", "5 秒") }
    static var interval10:  String { tr("interval.10", "10 秒") }

    // MARK: - Theme Mode

    static var themeSystem: String { tr("theme.system", "跟随系统") }
    static var themeLight:  String { tr("theme.light", "浅色") }
    static var themeDark:   String { tr("theme.dark", "深色") }

    // MARK: - Overview

    static var overviewMonitorHeader:   String { tr("overview.monitorHeader", "系统监控") }
    static var overviewActivityMonitor: String { tr("overview.activityMonitor", "活动监视器") }
    static var overviewNetwork:         String { tr("overview.network", "网络") }
    static var overviewProcessHeader:   String { tr("overview.processHeader", "进程") }

    // MARK: - Skin Settings

    static var skinHeader:       String { tr("settings.skin.header", "皮肤") }
    static var skinLibraryHeader: String { tr("settings.skin.libraryHeader", "皮肤库") }
    static var skinPathLabel:    String { tr("settings.skin.pathLabel", "路径") }
    static var skinPathPrompt:   String { tr("settings.skin.pathPrompt", "~/skins") }
    static var skinBrowse:       String { tr("settings.skin.browse", "浏览") }
    static var skinExtHeader:    String { tr("settings.skin.extHeader", "外部皮肤") }
    static var skinExtInfo:      String { tr("settings.skin.extInfo", "每个子文件夹为一个皮肤，内含 PNG 序列帧。\n文件夹名即皮肤名（如 01.cat → cat），同名会覆盖内置皮肤。") }
    static var skinPathNotFound: String { tr("settings.skin.pathNotFound", "路径不存在") }

    // MARK: - Metrics Settings

    static var metricsHeader: String { tr("settings.metrics.header", "菜单栏指标") }
    static var metricsFooter: String { tr("settings.metrics.footer", "勾选要在菜单栏图标旁显示的指标，拖动滑块设置颜色阈值。") }

    // MARK: - Performance Settings

    static var perfSourceLabel:  String { tr("performance.source.label", "动画驱动") }
    static var perfSourceHeader: String { tr("performance.source.header", "速度来源") }
    static var perfSourceFooter: String { tr("performance.source.footer", "动画速度将跟随所选指标实时变化。") }
    static var perfFpsLabel:     String { tr("performance.fps.label", "最高帧率") }
    static var perfFpsHeader:    String { tr("performance.fps.header", "帧率控制") }
    static var perfFpsFooter:    String { tr("performance.fps.footer", "限制最高帧率以降低 CPU 占用。") }
    static var perfSampleLabel:  String { tr("performance.sample.label", "采样频率") }
    static var perfSampleHeader: String { tr("performance.sample.header", "数据采样") }
    static var perfSampleFooter: String { tr("performance.sample.footer", "间隔越短，动画响应越快，但 CPU 占用略高。") }

    // MARK: - History Duration

    static var perfHistoryLabel:   String { tr("performance.history.label", "历史时长") }
    static var perfHistoryHeader:  String { tr("performance.history.header", "趋势图历史") }
    static var perfHistoryFooter:  String { tr("performance.history.footer", "趋势图显示的时间范围。时长越长占用更多内存。") }
    static var historyDuration5:   String { tr("historyDuration.5", "5 分钟") }
    static var historyDuration10:  String { tr("historyDuration.10", "10 分钟") }
    static var historyDuration15:  String { tr("historyDuration.15", "15 分钟") }
    static var historyDuration30:  String { tr("historyDuration.30", "30 分钟") }
    static var historyDuration60:  String { tr("historyDuration.60", "60 分钟") }

    // MARK: - General Settings

    static var generalStartupHeader: String { tr("general.startup.header", "启动") }
    static var generalStartupToggle: String { tr("general.startup.toggle", "开机自动启动") }
    static var generalStartupFooter: String { tr("general.startup.footer", "登录时自动在菜单栏启动 %@。") }
    static var generalLanguageHeader: String { tr("general.language.header", "语言") }
    static var generalLanguageSystem:  String { tr("general.language.system", "跟随系统") }

    // MARK: - About

    static var aboutInfoHeader:   String { tr("about.info.header", "信息") }
    static var aboutDeveloper:    String { tr("about.developer", "开发者") }
    static var aboutInspiration:  String { tr("about.inspiration", "灵感来源") }
    static var aboutQuit:         String { tr("about.quit", "退出 %@") }
    static var aboutVersion:      String { tr("about.version", "版本 %@") }

    // MARK: - Accessibility

    static var accSkinPreview: String { tr("acc.skinPreview", "当前皮肤预览") }
    static var accSelected:    String { tr("acc.selected", "，已选中") }
    static var accClickToOpen: String { tr("acc.clickToOpen", "，点击打开设置") }

    // MARK: - Pulsy Color Theme

    static var pulsyColorFire:       String { tr("pulsy.color.fire", "Fire") }
    static var pulsyColorOcean:      String { tr("pulsy.color.ocean", "Ocean") }
    static var pulsyColorMatrix:     String { tr("pulsy.color.matrix", "Matrix") }
    static var pulsyColorNeon:       String { tr("pulsy.color.neon", "Neon") }
    static var pulsyColorMonochrome: String { tr("pulsy.color.monochrome", "Monochrome") }

    // MARK: - Pulsy Waveform Style

    static var pulsyWaveEcg:      String { tr("pulsy.wave.ecg", "ECG") }
    static var pulsyWaveSine:     String { tr("pulsy.wave.sine", "Sine") }
    static var pulsyWaveSawtooth: String { tr("pulsy.wave.sawtooth", "Sawtooth") }
    static var pulsyWaveSquare:   String { tr("pulsy.wave.square", "Square") }
    static var pulsyWaveSpike:    String { tr("pulsy.wave.spike", "Spike") }

    // MARK: - Pulsy Settings

    static var pulsySettingsHeader:              String { tr("pulsy.settings.header", "Pulsy 控制台") }
    static var pulsySettingsColorTheme:          String { tr("pulsy.settings.colorTheme", "Color Theme") }
    static var pulsySettingsWaveform:            String { tr("pulsy.settings.waveform", "Waveform Style") }
    static var pulsySettingsLineWidth:           String { tr("pulsy.settings.lineWidth", "Line Width") }
    static var pulsySettingsGlowIntensity:       String { tr("pulsy.settings.glowIntensity", "Glow Intensity") }
    static var pulsySettingsAmplitudeSensitivity: String { tr("pulsy.settings.amplitudeSensitivity", "Amplitude Size") }
    static var pulsySettingsCalm:                String { tr("pulsy.settings.calm", "Calm") }
    static var pulsySettingsIntense:             String { tr("pulsy.settings.intense", "Intense") }

    // MARK: - Window

    static var windowTitle: String { tr("window.title", "设置") }

    // MARK: - Popover

    static func popoverHistoryFooter(_ duration: String) -> String {
        tr("popover.historyFooter", "%@ 历史").replacingOccurrences(of: "%@", with: duration)
    }
    static var popoverOpenMainWindow: String { tr("popover.openMainWindow", "打开主界面") }
    static var popoverProcessTopProcesses: String { tr("popover.process.topProcesses", "进程排行") }
    static var popoverProcessSampling: String { tr("popover.process.sampling", "正在采样进程活动...") }
    static var popoverProcessNoActivity: String { tr("popover.process.noActivity", "暂无活跃进程") }
    static var popoverCPUProcessesToggle: String { tr("popover.process.showCPU", "显示 CPU 进程") }
    static var popoverMemoryProcessesToggle: String { tr("popover.process.showMemory", "显示内存进程") }
    static var popoverProcessCPUHeader: String { tr("popover.process.cpuHeader", "% CPU") }
    static var popoverProcessMemoryHeader: String { tr("popover.process.memoryHeader", "内存 / %") }
    static var popoverNetworkTopProcesses: String { tr("popover.network.topProcesses", "进程排行") }
    static var popoverNetworkProcessHeader: String { tr("popover.network.processHeader", "下行 / 上行") }
    static var popoverNetworkProcessesToggle: String { tr("popover.network.toggle", "显示网络进程") }
    static var popoverNetworkDownload: String { tr("popover.network.download", "下行") }
    static var popoverNetworkUpload: String { tr("popover.network.upload", "上行") }
    static func popoverNetworkSortHelp(_ mode: String) -> String {
        tr("popover.network.sortHelp", "按%@排序").replacingOccurrences(of: "%@", with: mode)
    }
    static var popoverNetworkSortActivity: String { tr("popover.network.sort.activity", "活跃度") }
    static var popoverNetworkSortDownload: String { tr("popover.network.sort.download", "下行") }
    static var popoverNetworkSortUpload: String { tr("popover.network.sort.upload", "上行") }
    static var popoverNetworkSortTotal: String { tr("popover.network.sort.total", "总量") }
    static var popoverNetworkSortActivityShort: String { tr("popover.network.sort.activityShort", "活跃") }
    static var popoverNetworkSortDownloadShort: String { tr("popover.network.sort.downloadShort", "下行") }
    static var popoverNetworkSortUploadShort: String { tr("popover.network.sort.uploadShort", "上行") }
    static var popoverNetworkSortTotalShort: String { tr("popover.network.sort.totalShort", "总量") }
    static var popoverQuit: String { tr("popover.quit", "退出") }
    // MARK: - Update

    static var updateAutoCheckHeader:  String { tr("update.autoCheck.header", "更新") }
    static var updateAutoCheckToggle:  String { tr("update.autoCheck.toggle", "自动检查更新") }
    static var updateCheckNow:         String { tr("update.checkNow", "检查更新") }
    static var updateErrorDebug:       String { tr("update.error.debug", "调试模式下不支持检查更新。") }
    static var updateIntervalHeader:   String { tr("update.interval.header", "检查频率") }
    static var updateIntervalDaily:    String { tr("update.interval.daily", "每天") }
    static var updateIntervalWeekly:   String { tr("update.interval.weekly", "每周") }
    static var updateIntervalMonthly:  String { tr("update.interval.monthly", "每月") }
    static var updateAutoDownloadToggle: String { tr("update.autoDownload.toggle", "自动下载更新") }
    static var updateLastChecked:       String { tr("update.lastChecked", "上次检查：%@") }
    static var updateNeverChecked:      String { tr("update.neverChecked", "从未") }
}
