import AppKit
import ApplicationServices
import DylanCore

/// App notifications, replies and incoming calls in the notch (FR-68, FR-69, FR-82; design D27/D28).
/// macOS has no public API for other apps' notifications; Dylan reads the Notification Center banners
/// through Accessibility (spike T3.5) when they appear (AXObserver, no polling). Contents stay in memory.
/// Replies and Accept/Decline press the banner's own actions, so the app itself does the work.
final class NotificationProvider {
    static let shared = NotificationProvider()
    private static let bundleID = "com.apple.notificationcenterui"

    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var banners: [String: (banner: NotificationBanner, element: AXUIElement)] = [:]
    private var scanWork: DispatchWorkItem?
    private var launchObserver: NSObjectProtocol?
    private var retrying = false
    /// Messages per app within the grouping window ("WhatsApp · 3 messages").
    private var groups: [String: (count: Int, last: Date)] = [:]

    func start() {
        guard observer == nil else { return }
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else {
            watchLaunch()
            // Accessibility may be granted later in System Settings: look again in 10 s (one retry loop only).
            guard !retrying else { return }
            retrying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                MainActor.assumeIsolated {
                    NotificationProvider.shared.retrying = false
                    if AppModel.shared.features.isEnabled(.notifications) { NotificationProvider.shared.start() }
                }
            }
            return
        }
        pid = app.processIdentifier
        var o: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            MainActor.assumeIsolated { NotificationProvider.shared.changed() }
        }, &o) == .success, let o else { return }
        let el = AXUIElementCreateApplication(pid)
        for n in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(o, el, n as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o
        watchLaunch()
        // Banners already on screen are not news.
        for b in scan() { banners[b.banner.id] = b }
    }

    func stop() {
        if let o = observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        observer = nil
        scanWork?.cancel()
        for id in banners.keys { AppModel.shared.removeIfPresent("call-\(id)", now: Date()) }
        banners = [:]
        groups = [:]
    }

    /// Notification Center restarts (crash, update): attach again.
    private func watchLaunch() {
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard id == NotificationProvider.bundleID, AppModel.shared.features.isEnabled(.notifications) else { return }
                NotificationProvider.shared.stop()
                NotificationProvider.shared.start()
            }
        }
    }

    private func changed() {
        scanWork?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { NotificationProvider.shared.update() } }
        scanWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: w)
    }

    private func update() {
        let m = AppModel.shared
        guard m.features.isEnabled(.notifications) else { return }
        let now = Date()
        let current = scan()
        let ids = Set(current.map(\.banner.id))
        // Gone: a call that was answered elsewhere or dismissed.
        for (id, _) in banners where !ids.contains(id) {
            banners[id] = nil
            m.removeIfPresent("call-\(id)", now: now)
        }
        for b in current where banners[b.banner.id] == nil {
            banners[b.banner.id] = b
            guard NotificationRules.allowed(b.banner, apps: m.notificationApps) else { continue }
            b.banner.isCall ? postCall(b.banner, now: now) : postMessage(b.banner, now: now)
        }
        m.scheduleTick()
    }

    private func postMessage(_ b: NotificationBanner, now: Date) {
        let m = AppModel.shared
        let g = groups[b.app].flatMap { now.timeIntervalSince($0.last) < 60 ? $0 : nil }
        let count = (g?.count ?? 0) + 1
        groups[b.app] = (count, now)
        m.center.post(Activity(
            id: "notif-\(b.app)", kind: .notify, priority: .p1, state: .info, symbol: b.canReply ? "bubble.left.fill" : "bell.badge",
            label: TextRules.truncateTail(b.app, max: 10), value: count > 1 ? "\(count)" : "",
            detail: count > 1 ? L("notifications.group", b.app, count) + " · " + NotificationRules.detail(b) : NotificationRules.detail(b),
            genericDetail: L("notifications.generic", b.app), url: "notif:\(b.id)", startedAt: now), now: now)
    }

    private func postCall(_ b: NotificationBanner, now: Date) {
        let m = AppModel.shared
        var a = Activity(id: "call-\(b.id)", kind: .notify, priority: .p0, state: .needsAction, symbol: "phone.fill",
                         label: TextRules.truncateTail(b.title, max: 10), value: "",
                         detail: L("calls.incoming", b.title, b.body.isEmpty ? b.app : b.body),
                         genericDetail: L("calls.generic"), url: "call:\(b.id)", startedAt: now)
        a.endedAt = nil
        m.center.upsert(a)
        m.triggerP0(now: now)
    }

    // MARK: Actions

    func perform(_ action: String, bannerID: String) {
        guard let entry = banners[bannerID] else { return }
        let b = entry.banner
        let name: String?
        switch action {
        case "open": name = "AXPress"
        case "close": name = b.closeAction
        case "reply": name = b.replyAction
        case "accept": name = b.acceptAction
        case "decline": name = b.declineAction
        default: name = nil
        }
        guard let name, let raw = Self.rawAction(entry.element, named: name) else { return }
        AXUIElementPerformAction(entry.element, raw as CFString)
        if action != "reply" { AppModel.shared.removeIfPresent(b.isCall ? "call-\(bannerID)" : "notif-\(b.app)", now: Date()) }
    }

    func banner(_ id: String) -> NotificationBanner? { banners[id]?.banner }

    // MARK: Accessibility

    private func scan() -> [(banner: NotificationBanner, element: AXUIElement)] {
        guard pid > 0 else { return [] }
        var out: [(NotificationBanner, AXUIElement)] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 8 else { return }
            if Self.string(el, kAXSubroleAttribute) == "AXNotificationCenterBanner" {
                var title: String?, subtitle: String?, body: String?
                for c in Self.children(el) {
                    switch Self.string(c, kAXIdentifierAttribute) {
                    case "title": title = Self.string(c, kAXValueAttribute)
                    case "subtitle": subtitle = Self.string(c, kAXValueAttribute)
                    case "body": body = Self.string(c, kAXValueAttribute)
                    default: break
                    }
                }
                var names: CFArray?
                AXUIElementCopyActionNames(el, &names)
                if let b = NotificationBanner(id: Self.string(el, kAXIdentifierAttribute) ?? "", description: Self.string(el, kAXDescriptionAttribute),
                                              title: title, subtitle: subtitle, body: body, actionNames: names as? [String] ?? []) {
                    out.append((b, el))
                }
                return
            }
            for c in Self.children(el) { walk(c, depth + 1) }
        }
        var wins: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &wins) == .success else { return [] }
        for w in (wins as? [AXUIElement] ?? []) where Self.string(w, kAXSubroleAttribute) == "AXSystemDialog" { walk(w, 0) }
        return out
    }

    private static func rawAction(_ el: AXUIElement, named name: String) -> String? {
        var names: CFArray?
        AXUIElementCopyActionNames(el, &names)
        return (names as? [String] ?? []).first { NotificationBanner.actionName($0) == name }
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v as? String : nil
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success ? (v as? [AXUIElement] ?? []) : []
    }
}
