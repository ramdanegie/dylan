import AppKit
import DylanCore
import SwiftUI

/// Lock screen widgets (FR-80, experimental, spike T4.1): clock, Now Playing, battery and weather above the
/// lock screen. Only private SkyLight calls can put a window there (a space at the lock-screen level); they are
/// looked up with dlsym, and if any is missing or fails, the feature turns itself off. Off by default.
final class LockScreenProvider {
    static let shared = LockScreenProvider()
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var space: Int32 = 0
    private(set) var unavailable = false

    func start() {
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenProvider.shared.locked() }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenProvider.shared.unlocked() }
        })
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
        unlocked()
    }

    private func locked() {
        guard AppModel.shared.features.isEnabled(.lockScreen), !unavailable, panel == nil, let screen = NSScreen.main else { return }
        let size = NSSize(width: 420, height: 150)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - 120, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: LockScreenWidgets().environment(\.colorScheme, .dark))
        p.orderFrontRegardless()
        guard let s = SkyLight.moveToLockScreen(windowNumber: p.windowNumber) else {
            // macOS refused (or the private symbols are gone): never try again this run.
            unavailable = true
            p.close()
            return
        }
        space = s
        panel = p
    }

    private func unlocked() {
        if space != 0 { SkyLight.destroy(space: space); space = 0 }
        panel?.close()
        panel = nil
    }
}

/// The three private calls, resolved at runtime. Nothing is linked, so a future macOS without them only
/// disables this feature.
enum SkyLight {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias SpaceDestroy = @convention(c) (Int32, Int32) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func fn<T>(_ name: String, _: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    /// Level of the lock screen's shield; the space sits just above it.
    private static let lockScreenLevel: Int32 = 400

    static func moveToLockScreen(windowNumber: Int) -> Int32? {
        guard let main = fn("SLSMainConnectionID", MainConnection.self),
              let create = fn("SLSSpaceCreate", SpaceCreate.self),
              let setLevel = fn("SLSSpaceSetAbsoluteLevel", SpaceSetLevel.self),
              let show = fn("SLSShowSpaces", ShowSpaces.self),
              let add = fn("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self) else { return nil }
        let cid = main()
        let space = create(cid, 1, 0)
        guard space != 0, setLevel(cid, space, lockScreenLevel) == 0 else { return nil }
        _ = show(cid, [space] as CFArray)
        guard add(cid, space, [windowNumber] as CFArray, 7) == 0 else { destroy(space: space); return nil }
        return space
    }

    static func destroy(space: Int32) {
        guard let main = fn("SLSMainConnectionID", MainConnection.self), let d = fn("SLSSpaceDestroy", SpaceDestroy.self) else { return }
        _ = d(main(), space)
    }
}

/// Clock, Now Playing, battery, weather (design: lock.display). Read-only; no controls on the lock screen.
struct LockScreenWidgets: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                if let b = model.battery { Label("\(b.percent)%", systemImage: b.isCharging ? "battery.100percent.bolt" : "battery.75percent") }
                if let w = WeatherProvider.shared.current { Label("\(Int(w.temperature.rounded()))°", systemImage: Weather.describe(w.code).symbol) }
            }
            .font(DY.font(13, .semibold)).foregroundStyle(DY.fg)
            if let m = model.media, m.isPlaying {
                HStack(spacing: 10) {
                    Artwork(image: m.artwork, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        SwiftUI.Text(m.title).font(DY.font(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                        SwiftUI.Text(m.artist).font(DY.font(11.5)).foregroundStyle(DY.fg2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Equalizer(playing: true, color: model.mediaAccent)
                }
                .padding(10).frame(width: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
