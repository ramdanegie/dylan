import CoreGraphics

public enum NotchState: String, Sendable, CaseIterable {
    case closed, compact, peek, expanded
}

/// Where the notch is and how big each state is. PRD §2.4, design "Ukuran per state".
/// Computed from the screen at runtime; nothing about the hardware is hard-coded.
public struct NotchGeometry: Equatable, Sendable {
    public static let ear: CGFloat = 96          // ≤ 100 per side
    public static let peekExtra: CGFloat = 44
    public static let peekWidth: CGFloat = 372
    public static let peekMaxWidth: CGFloat = 420
    public static let expandedSize = CGSize(width: 640, height: 270)
    public static let expandedWideSize = CGSize(width: 720, height: 330)
    public static let expandedMax = CGSize(width: 720, height: 380)
    /// Extra room around the largest shape for the P0 pulse ring (16 pt).
    public static let panelMargin: CGFloat = 20
    public static let pillTop: CGFloat = 6
    public static let pillHeight: CGFloat = 32
    public static let pillClosedWidth: CGFloat = 200

    public let screen: CGRect
    public let hasNotch: Bool
    /// Physical notch size (or the pill size when there is no notch).
    public let notch: CGSize
    /// Horizontal centre of the notch in screen coordinates.
    public let centerX: CGFloat
    /// Ear width per side; "small" Compact uses 72 pt (FR-78).
    public var ear: CGFloat = NotchGeometry.ear

    /// - Parameters:
    ///   - screen: `NSScreen.frame` (AppKit coordinates, origin bottom-left).
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`; 0 on screens without a notch.
    ///   - leftAuxWidth / rightAuxWidth: widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    public init(screen: CGRect, safeAreaTop: CGFloat, leftAuxWidth: CGFloat?, rightAuxWidth: CGFloat?) {
        self.screen = screen
        if safeAreaTop > 0, let l = leftAuxWidth, let r = rightAuxWidth, screen.width - l - r > 0 {
            hasNotch = true
            notch = CGSize(width: screen.width - l - r, height: safeAreaTop)
            centerX = screen.minX + l + (screen.width - l - r) / 2
        } else {
            hasNotch = false
            notch = CGSize(width: Self.pillClosedWidth, height: Self.pillHeight)
            centerX = screen.midX
        }
    }

    public func size(for state: NotchState, wide: Bool = false, expandedHeight: CGFloat? = nil) -> CGSize {
        switch state {
        case .closed:
            return notch
        case .compact:
            return CGSize(width: notch.width + 2 * ear, height: notch.height)
        case .peek:
            let w = min(max(Self.peekWidth, notch.width + 2 * 80), Self.peekMaxWidth)
            return CGSize(width: w, height: notch.height + Self.peekExtra)
        case .expanded:
            let base = wide ? Self.expandedWideSize : Self.expandedSize
            let h = min(max(expandedHeight ?? base.height, 218), Self.expandedMax.height)
            return CGSize(width: base.width, height: h)
        }
    }

    /// Bottom corner radius per state (design: 9 · 12 · 18 · 30; pill 16 · 22 · 28).
    public func radius(for state: NotchState) -> CGFloat {
        switch (state, hasNotch) {
        case (.closed, true): return 9
        case (.compact, true): return 12
        case (.peek, true): return 18
        case (.expanded, true): return 30
        case (.closed, false), (.compact, false): return Self.pillHeight / 2
        case (.peek, false): return 22
        case (.expanded, false): return 28
        }
    }

    /// The fixed panel frame: large enough for the biggest state, top edge on the screen edge.
    public var panelFrame: CGRect {
        let w = Self.expandedMax.width + 2 * Self.panelMargin
        let h = Self.expandedMax.height + Self.panelMargin + (hasNotch ? 0 : Self.pillTop)
        return CGRect(x: (centerX - w / 2).rounded(), y: screen.maxY - h, width: w, height: h)
    }

    /// Frame of the visible shape for a state, in screen coordinates (used for hit-testing).
    public func shapeFrame(for state: NotchState, wide: Bool = false, expandedHeight: CGFloat? = nil) -> CGRect {
        let s = size(for: state, wide: wide, expandedHeight: expandedHeight)
        let top = screen.maxY - (hasNotch ? 0 : Self.pillTop)
        return CGRect(x: centerX - s.width / 2, y: top - s.height, width: s.width, height: s.height)
    }
}
