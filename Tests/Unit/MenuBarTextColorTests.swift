import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import TrayPulsy

/// 菜单栏文字颜色的默认值必须是「跟随系统」。
///
/// macOS 会按壁纸/系统外观把菜单栏图标自动换成黑或白，文字若被钉在某个固定色
/// （哪怕是很保险的白色）就会在一半的桌面上失效——这正是之前把默认值写成「纯白」
/// 后被用户发现的问题。默认走动态色 `labelColor`，「自定义」只作为主动选择的兜底。
@MainActor
final class MenuBarTextColorTests: XCTestCase {

    private var saved: FloatingWindowColor = .followsSystem

    override func setUp() {
        super.setUp()
        saved = Defaults[.statusBarTextColor]
    }

    override func tearDown() {
        Defaults[.statusBarTextColor] = saved
        super.tearDown()
    }

    func testDefaultValueFollowsSystem() {
        Defaults.reset(.statusBarTextColor)
        XCTAssertTrue(Defaults[.statusBarTextColor].isFollowsSystem)
        XCTAssertNil(MenuBarTextColorPolicy.resolvedColor(for: Defaults[.statusBarTextColor]))
    }

    func testFollowSystemResolvesToNilSoViewUsesDynamicLabelColor() {
        XCTAssertNil(MenuBarTextColorPolicy.resolvedColor(for: .followsSystem))
    }

    func testCustomColorResolvesToItsOwnComponents() throws {
        let stored = FloatingWindowColor(red: 0.25, green: 0.5, blue: 0.75)
        let color = try XCTUnwrap(
            MenuBarTextColorPolicy.resolvedColor(for: stored)?.usingColorSpace(.sRGB)
        )
        XCTAssertEqual(color.redComponent, 0.25, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0.75, accuracy: 0.001)
    }

    /// 用户从取色器选出来的颜色永远不能长得像哨兵——否则「自定义」会被悄悄当成「跟随系统」。
    ///
    /// 已实测：广色域颜色（Display P3 纯红/纯绿）经 `NSColor(Color).usingColorSpace(.sRGB)`
    /// 得到的都是有界 sRGB，分量被夹在 0…1（P3 纯红 → sRGB(1.000, 0, 0)），不会出现负分量。
    /// 这条断言把这个不变量钉住：日后若有人把转换改成 extended sRGB 之类，会立刻失败。
    func testPickedColorsNeverLookLikeTheSentinel() {
        let picked = [
            Color(.displayP3, red: 1, green: 0, blue: 0),
            Color(.displayP3, red: 0, green: 1, blue: 0),
            Color(.sRGB, red: 1, green: 1, blue: 1),
            Color(.sRGB, red: 0, green: 0, blue: 0),
        ].map { FloatingWindowColor(color: $0) }

        for color in picked {
            XCTAssertFalse(color.isFollowsSystem, "选出来的颜色不能被识别成哨兵")
            XCTAssertGreaterThanOrEqual(color.red, 0)
            XCTAssertGreaterThanOrEqual(color.green, 0)
            XCTAssertGreaterThanOrEqual(color.blue, 0)
        }
    }

    /// 纯白的「自定义」不能被当成哨兵；哨兵只有负分量一种形式。
    func testOpaqueWhiteIsCustomNotFollowSystem() {
        let white = FloatingWindowColor(red: 1, green: 1, blue: 1)
        XCTAssertFalse(white.isFollowsSystem)
        XCTAssertEqual(MenuBarTextColorPolicy.mode(for: white), .custom)
    }

    func testModeIsDerivedFromStoredValue() {
        XCTAssertEqual(MenuBarTextColorPolicy.mode(for: .followsSystem), .followsSystem)
        XCTAssertEqual(MenuBarTextColorPolicy.mode(for: .defaultText), .custom)
    }

    func testSwitchingToCustomSeedsADarkColorWhenNothingWasChosen() {
        let stored = MenuBarTextColorPolicy.storedValue(for: .custom, current: .followsSystem)
        XCTAssertFalse(stored.isFollowsSystem)
        XCTAssertEqual(stored, MenuBarTextColorPolicy.customSeed)
    }

    func testSwitchingToCustomKeepsAPreviouslyChosenColor() {
        let chosen = FloatingWindowColor(red: 0.1, green: 0.2, blue: 0.3)
        let stored = MenuBarTextColorPolicy.storedValue(for: .custom, current: chosen)
        XCTAssertEqual(stored, chosen)
    }

    func testSwitchingBackToSystemRestoresTheSentinel() {
        let stored = MenuBarTextColorPolicy.storedValue(
            for: .followsSystem,
            current: FloatingWindowColor(red: 0.1, green: 0.2, blue: 0.3)
        )
        XCTAssertTrue(stored.isFollowsSystem)
        XCTAssertNil(MenuBarTextColorPolicy.resolvedColor(for: stored))
    }

    /// 哨兵必须是可持久化的（负分量经 Codable + Defaults 往返后语义不变）。
    func testSentinelRoundTripsThroughDefaults() {
        Defaults[.statusBarTextColor] = .followsSystem
        XCTAssertTrue(Defaults[.statusBarTextColor].isFollowsSystem)

        let custom = FloatingWindowColor(red: 0.4, green: 0.4, blue: 0.4)
        Defaults[.statusBarTextColor] = custom
        XCTAssertEqual(Defaults[.statusBarTextColor], custom)
        XCTAssertFalse(Defaults[.statusBarTextColor].isFollowsSystem)
    }

    /// 「跟随系统」之所以成立，靠的是 `labelColor` 是**动态色**：同一个颜色对象在浅色
    /// 菜单栏下解析成深色、在深色下解析成浅色——这正是固定色做不到的事，也是把它当默认
    /// 值的唯一理由。若哪天有人把默认值换回固定色，这条会跟着失效。
    func testLabelColorResolvesPerMenuBarAppearance() throws {
        let light = try XCTUnwrap(NSAppearance(named: .vibrantLight))
        let dark = try XCTUnwrap(NSAppearance(named: .vibrantDark))

        var lightBrightness: CGFloat = -1
        light.performAsCurrentDrawingAppearance {
            lightBrightness = NSColor.labelColor.usingColorSpace(.sRGB)?.brightnessComponent ?? -1
        }
        var darkBrightness: CGFloat = -1
        dark.performAsCurrentDrawingAppearance {
            darkBrightness = NSColor.labelColor.usingColorSpace(.sRGB)?.brightnessComponent ?? -1
        }

        XCTAssertLessThan(lightBrightness, 0.5, "浅色菜单栏下 labelColor 应解析为深色文字")
        XCTAssertGreaterThan(darkBrightness, 0.5, "深色菜单栏下 labelColor 应解析为浅色文字")
    }
}
