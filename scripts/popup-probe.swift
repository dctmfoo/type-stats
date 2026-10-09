// Drives and measures the real menu bar popup of a running TypeStats (needs Accessibility permission).
// Usage: swift scripts/popup-probe.swift <command> <pid> [arg]
//   item <pid>          centre of the status item, as "x y" (click it to open the popup)
//   window <pid>        "window id<TAB>x<TAB>y<TAB>w<TAB>h" of the open popup, from the window server
//   measure <pid>       "window" and "detail" in one read: id, x, y, w, h and detail height, tab separated
//   detail <pid>        height of the popup's detail area (charts and Top apps; it scrolls on a short screen) in points
//   period <pid> <0-2>  press the Today, 7 days or 30 days button
// Exits 1 when what it looks for is not there (popup closed, no status item).
import ApplicationServices
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[2]) else {
    FileHandle.standardError.write(Data("usage: popup-probe.swift item|window|detail|period <pid> [n]\n".utf8))
    exit(2)
}
let app = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func rect(_ element: AXUIElement) -> CGRect? {
    var origin = CGPoint(), size = CGSize()
    guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
          AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}
func descendants(_ element: AXUIElement) -> [AXUIElement] {
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return children + children.flatMap(descendants)
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("popup-probe: \(message)\n".utf8))
    exit(1)
}

func popupWindow() -> (id: Int, frame: CGRect, element: AXUIElement)? {
    // The popup is open while the app has an accessibility window; the window server's entry for it
    // reports "off screen", so match its id by the frame.
    guard let window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first, let r = rect(window) else { return nil }
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let id = list.first { w in
        guard (w[kCGWindowOwnerPID as String] as? Int) == Int(pid), (w[kCGWindowLayer as String] as? Int) == 101,
              let b = w[kCGWindowBounds as String] as? [String: Double] else { return false }
        return Int((b["X"] ?? -1).rounded()) == Int(r.minX.rounded()) && Int((b["Y"] ?? -1).rounded()) == Int(r.minY.rounded())
            && Int((b["Width"] ?? -1).rounded()) == Int(r.width.rounded()) && Int((b["Height"] ?? -1).rounded()) == Int(r.height.rounded())
    }?[kCGWindowNumber as String] as? Int ?? 0
    return (id, r, window)
}
func detailHeight(in window: AXUIElement) -> Int? {
    guard let area = descendants(window).first(where: { attribute($0, kAXIdentifierAttribute) as? String == "detail" }),
          let r = rect(area) else { return nil }
    return Int(r.height.rounded())
}
func line(_ numbers: [Int]) -> String { numbers.map(String.init).joined(separator: "\t") }

switch args[1] {
case "item":
    guard let bar = attribute(app, "AXExtrasMenuBar"),
          let item = (attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement])?.first,
          let r = rect(item) else { fail("no status item") }
    print(Int(r.midX), Int(r.midY))
case "window":
    guard let w = popupWindow() else { fail("popup window is not open") }
    print(line([w.id] + [w.frame.minX, w.frame.minY, w.frame.width, w.frame.height].map { Int($0.rounded()) }))
case "measure":
    guard let w = popupWindow() else { fail("popup window is not open") }
    guard let detail = detailHeight(in: w.element) else { fail("no detail area in the popup") }
    print(line([w.id] + [w.frame.minX, w.frame.minY, w.frame.width, w.frame.height].map { Int($0.rounded()) } + [detail]))
case "detail":
    guard let w = popupWindow() else { fail("popup window is not open") }
    guard let detail = detailHeight(in: w.element) else { fail("no detail area in the popup") }
    print(detail)
case "period":
    guard args.count > 3, let index = Int(args[3]),
          let window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { fail("popup window is not open") }
    let buttons = descendants(window).filter { attribute($0, kAXIdentifierAttribute) as? String == "period" }
    guard index < buttons.count else { fail("no period button \(index)") }
    exit(AXUIElementPerformAction(buttons[index], kAXPressAction as CFString) == .success ? 0 : 1)
default:
    fail("unknown command \(args[1])")
}
