import AppKit
import XCTest
@testable import TrayPulsy

final class PulsySkinRendererTests: XCTestCase {

    // MARK: - Frame generation

    func testGenerateFrames_returnsCorrectCount() {
        let frames = PulsySkinRenderer.generateFrames()
        XCTAssertEqual(frames.count, PulsySkinRenderer.frameCount)
    }

    func testGenerateFrames_allFramesHaveCorrectSize() {
        for frame in PulsySkinRenderer.generateFrames() {
            XCTAssertEqual(frame.size.width, 18)
            XCTAssertEqual(frame.size.height, 18)
        }
    }

    func testGenerateFrames_withValue_returnsCorrectCount() {
        let frames = PulsySkinRenderer.generateFrames(value: 50)
        XCTAssertEqual(frames.count, PulsySkinRenderer.frameCount)
    }

    func testGenerateFrames_differentValues_produceDifferentFrames() {
        let idle = PulsySkinRenderer.generateFrames(value: 0)
        let highLoad = PulsySkinRenderer.generateFrames(value: 90)

        // Frame 0 is the preview frame — should differ because amplitude differs
        XCTAssertFalse(idle[0] === highLoad[0])
    }

    // MARK: - Waveform

    func testEcgValue_atBaseline_isNearZero() {
        // Between T wave and next P wave → should be ~0
        let value = PulsySkinRenderer.ecgValue(at: 0.7)
        XCTAssertEqual(value, 0, accuracy: 0.01)
    }

    func testEcgValue_rPeak_isPositive() {
        let value = PulsySkinRenderer.ecgValue(at: 0.27)
        XCTAssertGreaterThan(value, 0.5)
    }

    func testEcgValue_sDip_isNegative() {
        let value = PulsySkinRenderer.ecgValue(at: 0.30)
        XCTAssertLessThan(value, 0)
    }

    func testEcgValue_rPeakScalesWithMultiplier() {
        let low = PulsySkinRenderer.ecgValue(at: 0.27, rPeak: 0.5)
        let high = PulsySkinRenderer.ecgValue(at: 0.27, rPeak: 1.5)
        XCTAssertGreaterThan(high, low)
    }

    func testEcgValue_isPeriodic() {
        let v1 = PulsySkinRenderer.ecgValue(at: 0.3)
        let v2 = PulsySkinRenderer.ecgValue(at: 1.3)
        XCTAssertEqual(v1, v2, accuracy: 0.001)
    }

    // MARK: - Waveform styles via waveformValue

    func testWaveformValue_ecgMatchesEcgValue() {
        let v1 = PulsySkinRenderer.waveformValue(at: 0.27, rPeak: 0.85, style: .ecg)
        let v2 = PulsySkinRenderer.ecgValue(at: 0.27, rPeak: 0.85)
        XCTAssertEqual(v1, v2, accuracy: 0.001)
    }

    func testWaveformValue_sine_positivePeak() {
        let v = PulsySkinRenderer.waveformValue(at: 0.25, rPeak: 1.0, style: .sine)
        XCTAssertEqual(v, 1.0, accuracy: 0.01)
    }

    func testWaveformValue_sine_negativeTrough() {
        let v = PulsySkinRenderer.waveformValue(at: 0.75, rPeak: 1.0, style: .sine)
        XCTAssertEqual(v, 0.0, accuracy: 0.01)
    }

    func testWaveformValue_sine_scalesWithRPeak() {
        let low = PulsySkinRenderer.waveformValue(at: 0.25, rPeak: 0.5, style: .sine)
        let high = PulsySkinRenderer.waveformValue(at: 0.25, rPeak: 1.5, style: .sine)
        XCTAssertGreaterThan(high, low)
    }

    func testWaveformValue_square_highPlateau() {
        let v = PulsySkinRenderer.waveformValue(at: 0.2, rPeak: 1.0, style: .square)
        XCTAssertEqual(v, 1.0, accuracy: 0.01)
    }

    func testWaveformValue_sawtooth_risesThenFalls() {
        let mid = PulsySkinRenderer.waveformValue(at: 0.35, rPeak: 1.0, style: .sawtooth)
        let peak = PulsySkinRenderer.waveformValue(at: 0.6, rPeak: 1.0, style: .sawtooth)
        XCTAssertGreaterThan(peak, mid)
    }

    func testWaveformValue_spike_peakAtCenter() {
        let center = PulsySkinRenderer.waveformValue(at: 0.5, rPeak: 1.0, style: .spike)
        let offCenter = PulsySkinRenderer.waveformValue(at: 0.3, rPeak: 1.0, style: .spike)
        XCTAssertGreaterThan(center, offCenter)
    }

    func testWaveformValue_isPeriodic() {
        for style in PulsyWaveformStyle.allCases {
            let v1 = PulsySkinRenderer.waveformValue(at: 0.3, rPeak: 1.0, style: style)
            let v2 = PulsySkinRenderer.waveformValue(at: 1.3, rPeak: 1.0, style: style)
            XCTAssertEqual(v1, v2, accuracy: 0.001, "Periodicity failed for \(style)")
        }
    }

    // MARK: - Config-based frame generation

    func testGenerateFrames_withConfig_returnsCorrectCount() {
        let config = PulsyConfig(colorTheme: .ocean, waveformStyle: .sine,
                                  lineWidth: 2.0, glowIntensity: 1.5, amplitudeSensitivity: 1.0)
        let frames = PulsySkinRenderer.generateFrames(value: 50, config: config)
        XCTAssertEqual(frames.count, PulsySkinRenderer.frameCount)
    }

    func testGenerateFrames_differentThemes_produceDifferentFrames() {
        let fireConfig = PulsyConfig.defaults
        let oceanConfig = PulsyConfig(colorTheme: .ocean, waveformStyle: .ecg,
                                       lineWidth: 1.5, glowIntensity: 1.0, amplitudeSensitivity: 1.0)
        let fireFrames = PulsySkinRenderer.generateFrames(value: 50, config: fireConfig)
        let oceanFrames = PulsySkinRenderer.generateFrames(value: 50, config: oceanConfig)
        // Different color themes should produce different images
        XCTAssertFalse(fireFrames[0] === oceanFrames[0])
    }

    func testGenerateFrames_differentStyles_produceDifferentFrames() {
        let ecgConfig = PulsyConfig(colorTheme: .fire, waveformStyle: .ecg,
                                     lineWidth: 1.5, glowIntensity: 1.0, amplitudeSensitivity: 1.0)
        let sineConfig = PulsyConfig(colorTheme: .fire, waveformStyle: .sine,
                                      lineWidth: 1.5, glowIntensity: 1.0, amplitudeSensitivity: 1.0)
        let ecgFrames = PulsySkinRenderer.generateFrames(value: 50, config: ecgConfig)
        let sineFrames = PulsySkinRenderer.generateFrames(value: 50, config: sineConfig)
        XCTAssertFalse(ecgFrames[0] === sineFrames[0])
    }
}
