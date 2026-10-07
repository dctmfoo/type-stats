import CoreGraphics
import Foundation

/// Finds which process owns the window under a click, from a front-to-back window
/// list (as `CGWindowListCopyWindowInfo` returns it). Pure, so it is testable.
public enum WindowHitTest {
    public struct Window: Sendable {
        public let pid: Int32
        public let layer: Int
        public let bounds: CGRect
        public let alpha: Double

        public init(pid: Int32, layer: Int, bounds: CGRect, alpha: Double = 1) {
            self.pid = pid
            self.layer = layer
            self.bounds = bounds
            self.alpha = alpha
        }

        /// Builds a window from one `CGWindowListCopyWindowInfo` entry.
        public init?(info: [String: Any]) {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            self.init(pid: pid, layer: layer, bounds: bounds,
                      alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }

    /// Windows at or above the Dock level (the Dock's full-screen window, the menu bar,
    /// status items, overlays, the cursor) are skipped: on this Mac the Dock and some
    /// apps keep invisible full-screen windows there that do not take clicks.
    public static let maxLayer = Int(CGWindowLevelForKey(.dockWindow))

    /// The owner of the frontmost visible normal or floating window containing `point`
    /// (global display coordinates, origin top-left), or nil.
    public static func ownerPID(at point: CGPoint, windows: [Window]) -> Int32? {
        windows.first { $0.layer >= 0 && $0.layer < maxLayer && $0.alpha > 0 && $0.bounds.contains(point) }?.pid
    }
}
