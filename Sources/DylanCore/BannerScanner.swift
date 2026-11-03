import ApplicationServices

/// Finds the Notification Center banners on screen (spike T3.5): windows with subrole AXSystemDialog, then
/// AXNotificationCenterBanner groups with title/subtitle/body texts. Needs Accessibility.
public enum BannerScanner {
    public static func scan(pid: pid_t) -> [(banner: NotificationBanner, element: AXUIElement)] {
        var out: [(NotificationBanner, AXUIElement)] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 8 else { return }
            if string(el, kAXSubroleAttribute) == "AXNotificationCenterBanner" {
                var title: String?, subtitle: String?, body: String?
                for c in children(el) {
                    switch string(c, kAXIdentifierAttribute) {
                    case "title": title = string(c, kAXValueAttribute)
                    case "subtitle": subtitle = string(c, kAXValueAttribute)
                    case "body": body = string(c, kAXValueAttribute)
                    default: break
                    }
                }
                var names: CFArray?
                AXUIElementCopyActionNames(el, &names)
                if let b = NotificationBanner(id: string(el, kAXIdentifierAttribute) ?? "", description: string(el, kAXDescriptionAttribute),
                                              title: title, subtitle: subtitle, body: body, actionNames: names as? [String] ?? []) {
                    out.append((b, el))
                }
                return
            }
            for c in children(el) { walk(c, depth + 1) }
        }
        var wins: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &wins) == .success else { return [] }
        for w in (wins as? [AXUIElement] ?? []) where string(w, kAXSubroleAttribute) == "AXSystemDialog" { walk(w, 0) }
        return out
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v as? String : nil
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success ? (v as? [AXUIElement] ?? []) : []
    }
}
