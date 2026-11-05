import AppKit
import DylanCore
import SwiftUI

/// Island style (FR-112, design D59). On a real notch the part over the camera housing stays black; the style
/// applies to Peek and Expanded. Floating lifts the pill off the top edge on screens without a notch.
enum IslandStyle: String, CaseIterable, Identifiable {
    case black, color, glass, frosted, floating
    var id: String { rawValue }
}

/// Settings added with the v1.5 design (D51–D60): look, animations, focus, lyrics and Home modules.
/// Observable so the notch redraws when a toggle changes in Settings.
@Observable
final class Prefs {
    static let shared = Prefs()
    private var d: UserDefaults { AppModel.store }

    // MARK: Island look (D59)
    var style: IslandStyle { didSet { d.set(style.rawValue, forKey: "look.style") } }
    /// Hex of the tint for the Colour style.
    var styleColor: String { didSet { d.set(styleColor, forKey: "look.color") } }
    /// Floating island: gap to the top edge (0–12 pt) and extra width (0–120 pt).
    var floatGap: Double { didSet { d.set(floatGap, forKey: "look.floatGap") } }
    var floatWidth: Double { didSet { d.set(floatWidth, forKey: "look.floatWidth") } }
    /// Step aside when the cursor only passes by (screens without a notch).
    var dodgeMouse: Bool { didSet { d.set(dodgeMouse, forKey: "look.dodge") } }

    // MARK: Animations (D54); Reduce Motion turns all of them off
    var glowLine: Bool { didSet { d.set(glowLine, forKey: "anim.glow") } }
    var timeLine: Bool { didSet { d.set(timeLine, forKey: "anim.line") } }
    var stacked: Bool { didSet { d.set(stacked, forKey: "anim.stack") } }
    var confetti: Bool { didSet { d.set(confetti, forKey: "anim.confetti") } }
    var karaoke: Bool { didSet { d.set(karaoke, forKey: "anim.karaoke") } }

    // MARK: Lyrics (D53)
    var romanize: Bool { didSet { d.set(romanize, forKey: "lyrics.romanize") } }
    var translate: Bool { didSet { d.set(translate, forKey: "lyrics.translate") } }

    // MARK: Notifications (D57)
    var holdDuringFocus: Bool { didSet { d.set(holdDuringFocus, forKey: "notif.holdFocus") } }
    /// 1 or 7 days.
    var historyDays: Int { didSet { d.set(historyDays, forKey: "notif.historyDays") } }

    // MARK: Focus (D58)
    var focusMinutes: Int { didSet { d.set(focusMinutes, forKey: "pomo.focus") } }
    var shortBreakMinutes: Int { didSet { d.set(shortBreakMinutes, forKey: "pomo.short") } }
    var longBreakMinutes: Int { didSet { d.set(longBreakMinutes, forKey: "pomo.long") } }
    var autoBreak: Bool { didSet { d.set(autoBreak, forKey: "pomo.autoBreak") } }
    var autoFocus: Bool { didSet { d.set(autoFocus, forKey: "pomo.autoFocus") } }

    // MARK: Home modules (D59)
    var modules: [HomeModule] {
        didSet {
            d.set(modules.map(\.rawValue), forKey: "home.modules")
            // The radio's only controls live in its module.
            if !modules.contains(.radio) { RadioPlayer.shared.pause() }
        }
    }

    private init() {
        let d = AppModel.store
        style = IslandStyle(rawValue: d.string(forKey: "look.style") ?? "") ?? (d.bool(forKey: "glassPill") ? .glass : .black)
        styleColor = d.string(forKey: "look.color") ?? "#0F3D3E"
        floatGap = d.object(forKey: "look.floatGap") as? Double ?? 6
        floatWidth = d.object(forKey: "look.floatWidth") as? Double ?? 0
        dodgeMouse = d.bool(forKey: "look.dodge")
        glowLine = d.object(forKey: "anim.glow") as? Bool ?? true
        timeLine = d.object(forKey: "anim.line") as? Bool ?? true
        stacked = d.object(forKey: "anim.stack") as? Bool ?? true
        confetti = d.object(forKey: "anim.confetti") as? Bool ?? true
        karaoke = d.object(forKey: "anim.karaoke") as? Bool ?? true
        romanize = d.object(forKey: "lyrics.romanize") as? Bool ?? true
        translate = d.bool(forKey: "lyrics.translate")
        holdDuringFocus = d.bool(forKey: "notif.holdFocus")
        historyDays = d.object(forKey: "notif.historyDays") as? Int ?? 1
        focusMinutes = d.object(forKey: "pomo.focus") as? Int ?? 25
        shortBreakMinutes = d.object(forKey: "pomo.short") as? Int ?? 5
        longBreakMinutes = d.object(forKey: "pomo.long") as? Int ?? 15
        autoBreak = d.object(forKey: "pomo.autoBreak") as? Bool ?? true
        autoFocus = d.bool(forKey: "pomo.autoFocus")
        modules = (d.stringArray(forKey: "home.modules") ?? []).compactMap(HomeModule.init(rawValue:))
    }

    var pomodoro: PomodoroConfig {
        var c = PomodoroConfig()
        c.focus = TimeInterval(focusMinutes * 60)
        c.shortBreak = TimeInterval(shortBreakMinutes * 60)
        c.longBreak = TimeInterval(longBreakMinutes * 60)
        c.autoBreak = autoBreak
        c.autoFocus = autoFocus
        return c
    }

    /// Animations only run when the user has not asked macOS to reduce motion.
    static var motionAllowed: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Cards that can be added to Home with "Edit modules" (D59). Weather and Stats already have their own places.
enum HomeModule: String, CaseIterable, Identifiable {
    case tasks, flashcards, radio
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .tasks: return "checklist"
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .radio: return "dot.radiowaves.left.and.right"
        }
    }
}

extension NSColor {
    /// "#0F3D3E" or "0F3D3E".
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Blur behind the island for the glass styles before macOS 26 (D59).
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
