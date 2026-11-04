import ApplicationServices

/// Menu items by their keyboard shortcut (locale-independent), for meeting controls (FR-83). Needs Accessibility.
public enum AXMenu {
    /// The enabled menu item whose shortcut is ⌘ + `modifiers` (AX mask: Shift 1, Option 2, Control 4) + `key`.
    public static func find(pid: pid_t, key: Character, modifiers: Int) -> AXUIElement? {
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        func search(_ el: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 4 else { return nil }
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success else { return nil }
            for child in (v as? [AXUIElement] ?? []) {
                var ch: CFTypeRef?, mods: CFTypeRef?, enabled: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &ch) == .success,
                   (ch as? String)?.uppercased() == String(key).uppercased(),
                   AXUIElementCopyAttributeValue(child, kAXMenuItemCmdModifiersAttribute as CFString, &mods) == .success,
                   (mods as? Int) == modifiers,
                   AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabled) == .success, enabled as? Bool == true {
                    return child
                }
                if let found = search(child, depth: depth + 1) { return found }
            }
            return nil
        }
        return search(bar as! AXUIElement, depth: 0)
    }

    public static func title(_ el: AXUIElement) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v) == .success ? v as? String : nil
    }
}
