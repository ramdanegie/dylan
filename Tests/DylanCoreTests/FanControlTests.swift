import Foundation
import Testing
@testable import DylanCore
@testable import SMCKit

@Suite struct SMCCodecTests {
    @Test func fourcc() {
        #expect(SMC.fourcc("F0Ac") == 0x4630_4163)
        #expect(SMC.string(SMC.fourcc("flt ")) == "flt ")
    }

    @Test func decodeAndEncode() {
        // Bytes read on the M1 Pro spike: F0Mn = 1200.0 little-endian float, F0Md = 1.
        #expect(SMC.decode("flt ", [0x00, 0x00, 0x96, 0x44]) == 1200)
        #expect(SMC.decode("ui8 ", [1]) == 1)
        #expect(SMC.decode("ui16", [0x01, 0x02]) == 258)
        #expect(SMC.decode("sp78", [0x30, 0x80]) == 48.5)
        #expect(SMC.decode("fpe2", [0x1f, 0x40]) == 2000)
        #expect(SMC.decode("flt ", [1, 2]) == nil)          // wrong size
        #expect(SMC.encode(1200, type: "flt ") == [0x00, 0x00, 0x96, 0x44])
        #expect(SMC.encode(1, type: "ui8 ") == [1])
        #expect(SMC.encode(300, type: "ui8 ") == nil)
        #expect(SMC.encode(2000, type: "fpe2") == [0x1f, 0x40])
    }

    @Test func requestLayout() {
        let b = SMC.request("F1Tg", op: 6)
        #expect(b.count == 80)
        #expect(SMC.u32(b, 0) == SMC.fourcc("F1Tg"))
        #expect(b[42] == 6)
    }
}

@Suite struct FanControlTests {
    @Test func presetsFollowTheDesign() {
        #expect(FanPreset.auto.fraction(cpu: 99) == nil)
        #expect(FanPreset.curve.fraction(cpu: 99) == nil)
        #expect(FanPreset.quiet.fraction(cpu: 95) == 0.25)            // capped at 25 %
        #expect(FanPreset.quiet.fraction(cpu: 50) == 0)
        #expect(FanPreset.balanced.fraction(cpu: 40) == 0.08)          // floor 8 %
        #expect(FanPreset.performance.fraction(cpu: 30) == 0.40)       // floor 40 %
        #expect(FanPreset.performance.fraction(cpu: 120) == 1)
        #expect(FanPreset.max.fraction(cpu: 30) == 1)
        #expect(FanPreset.shortcuts.count == 5)
    }

    @Test func curveInterpolatesAndStaysMonotonic() {
        var c = FanCurve.standard
        #expect(c.percent(at: 20) == 10)
        #expect(c.percent(at: 50) == 20)
        #expect(c.percent(at: 99) == 100)
        c.set(1, 80)                                 // above the next point → next rises
        #expect(c.percents == [10, 80, 80, 100])
        c.set(3, 5)                                  // below everything → all drop
        #expect(c.percents == [5, 5, 5, 5])
        c.set(0, 150)
        #expect(c.percents == [100, 100, 100, 100])
    }

    @Test func rpmAndUnits() {
        #expect(FanMath.rpm(0, min: 1200, max: 5779) == 1200)
        #expect(FanMath.rpm(1, min: 1200, max: 5779) == 5780)
        #expect(FanMath.rpm(0.5, min: 1200, max: 6200) == 3700)
        #expect(FanMath.rpm(2, min: 1200, max: 6200) == 6200)
        #expect(FanMath.fahrenheit(100) == 212)
        #expect(FanMath.heat(79) == .normal && FanMath.heat(85) == .warm && FanMath.heat(90) == .hot)
    }

    @Test func smootherAveragesTheWindow() {
        var s = Smoother(window: 10)
        let t = Date(timeIntervalSince1970: 0)
        let out = [s.add(60, at: t), s.add(80, at: t + 5), s.add(100, at: t + 12)]
        #expect(out == [60, 70, 90])               // the first sample left the window at +12 s
    }

    @Test func heatWarningHoldsAndCoolsDown() {
        var w = HeatWatch(threshold: 95)
        let t = Date(timeIntervalSince1970: 0)
        let steps: [(Double, TimeInterval)] = [(97, 0), (96, 20), (97, 30), (97, 60), (90, 100), (97, 200), (97, 230), (97, 30 + 15 * 60)]
        // fires after 30 s, once; a new hot spell inside the 15 min wait stays quiet
        #expect(steps.map { w.overheated($0.0, at: t + $0.1) } == [false, false, true, false, false, false, false, true])
    }

    @Test func returnsToAutoAfterFiveCoolMinutes() {
        var w = HeatWatch()
        let t = Date(timeIntervalSince1970: 0)
        let steps: [(Double, TimeInterval)] = [(60, 0), (70, 200), (60, 210), (60, 510)]   // 70 °C resets the timer
        #expect(steps.map { w.cooledDown($0.0, at: t + $0.1) } == [false, false, false, true])
    }

    @Test func sensorsGroupedByAppleNames() {
        let r = ThermalSensors.summarize([("PMU tdie1", 42.5), ("PMU tdie8", 44.0), ("PMU TP1g", 41), ("PMU TP0s", 80),
                                          ("NAND CH0 temp", 36), ("gas gauge battery", 33.9), ("PMU tdie2", -40), ("PMU tcal", 51.9)])
        #expect(r[.cpu] == 44 && r[.gpu] == 41 && r[.ssd] == 36 && r[.battery] == 33.9)
    }
}
