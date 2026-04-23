import Defaults
import Foundation

/// Lightweight localization helper with runtime language switching.
/// Translations are compiled into the binary for maximum reliability
/// across all build environments (Xcode, swift run, make app).
///
/// To add/update translations: edit the `tables` dictionary below.
/// The .strings files in Resources/lang/ are kept as the human-readable
/// source of truth for translators but are NOT loaded at runtime.
enum L10n {

    // MARK: - Core

    static let languageDidChangeNotification = Notification.Name("L10n.languageDidChange")

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
        _strings[key] ?? defaultValue
    }

    /// Reload strings (call after language change).
    static func reload() {
        _strings = loadTable()
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

            // Skin Settings
            "settings.skin.header": "Skins",
            "settings.skin.pathLabel": "Path",
            "settings.skin.pathPrompt": "~/skins",
            "settings.skin.browse": "Browse",
            "settings.skin.extHeader": "External Skins",
            "settings.skin.extInfo": "Skin folders in this directory are loaded automatically. Skins with the same name override built-in skins.",
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

            // Window
            "window.title": "Settings",
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

            // Skin Settings
            "settings.skin.header": "皮肤",
            "settings.skin.pathLabel": "路径",
            "settings.skin.pathPrompt": "~/skins",
            "settings.skin.browse": "浏览",
            "settings.skin.extHeader": "外部皮肤",
            "settings.skin.extInfo": "目录下的皮肤文件夹会自动加载，同名会覆盖内置皮肤",
            "settings.skin.pathNotFound": "路径不存在",

            // Metrics Settings
            "settings.metrics.header": "菜单栏指标",
            "settings.metrics.footer": "勾选要在菜单栏图标旁显示的指标，拖动滑块设置颜色阈值。",

            // Performance Settings
            "performance.source.label": "动画驱动",
            "performance.source.header": "速度来源",
            "performance.source.footer": "猫咪动画速度将跟随所选指标实时变化。",
            "performance.fps.label": "最高帧率",
            "performance.fps.header": "帧率控制",
            "performance.fps.footer": "限制最高帧率以降低 CPU 占用。",
            "performance.sample.label": "采样频率",
            "performance.sample.header": "数据采样",
            "performance.sample.footer": "间隔越短，动画响应越快，但 CPU 占用略高。",

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
    static var metricOverviewDown:   String { tr("metric.overview.down", "下行") }
    static var metricOverviewUp:     String { tr("metric.overview.up", "上行") }

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

    // MARK: - Skin Settings

    static var skinHeader:       String { tr("settings.skin.header", "皮肤") }
    static var skinPathLabel:    String { tr("settings.skin.pathLabel", "路径") }
    static var skinPathPrompt:   String { tr("settings.skin.pathPrompt", "~/skins") }
    static var skinBrowse:       String { tr("settings.skin.browse", "浏览") }
    static var skinExtHeader:    String { tr("settings.skin.extHeader", "外部皮肤") }
    static var skinExtInfo:      String { tr("settings.skin.extInfo", "目录下的皮肤文件夹会自动加载，同名会覆盖内置皮肤") }
    static var skinPathNotFound: String { tr("settings.skin.pathNotFound", "路径不存在") }

    // MARK: - Metrics Settings

    static var metricsHeader: String { tr("settings.metrics.header", "菜单栏指标") }
    static var metricsFooter: String { tr("settings.metrics.footer", "勾选要在菜单栏图标旁显示的指标，拖动滑块设置颜色阈值。") }

    // MARK: - Performance Settings

    static var perfSourceLabel:  String { tr("performance.source.label", "动画驱动") }
    static var perfSourceHeader: String { tr("performance.source.header", "速度来源") }
    static var perfSourceFooter: String { tr("performance.source.footer", "猫咪动画速度将跟随所选指标实时变化。") }
    static var perfFpsLabel:     String { tr("performance.fps.label", "最高帧率") }
    static var perfFpsHeader:    String { tr("performance.fps.header", "帧率控制") }
    static var perfFpsFooter:    String { tr("performance.fps.footer", "限制最高帧率以降低 CPU 占用。") }
    static var perfSampleLabel:  String { tr("performance.sample.label", "采样频率") }
    static var perfSampleHeader: String { tr("performance.sample.header", "数据采样") }
    static var perfSampleFooter: String { tr("performance.sample.footer", "间隔越短，动画响应越快，但 CPU 占用略高。") }

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

    // MARK: - Window

    static var windowTitle: String { tr("window.title", "设置") }
}
