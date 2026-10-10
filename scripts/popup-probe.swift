// Drives and measures the real menu bar popup of a running TypeStats (needs Accessibility permission).
// Usage: swift scripts/popup-probe.swift <command> <pid> [arg]
//   item <pid>          centre of the status item, as "x y" (click it to open the popup)
//   window <pid>        "window id<TAB>x<TAB>y<TAB>w<TAB>h" of the open popup, from the window server
//   measure <pid>       "window" and "detail" in one read: id, x, y, w, h and detail height, tab separated
//   period <pid> <0-2>  press the Today, 7 days or 30 days button
//   hour <pid> <id>     centre of an accessible hourly cell (for pointer-only hover)
//   focus-hour <pid> <id> focus a cell without generating a typing event
//   hour-label <pid> <id> the cell's non-colour accessibility text
//   hour-detail <pid>   the visible hover/focus text
//   diagnostic <pid>    focused app PID and this test popup's open/frame state
// Exits 1 when what it looks for is not there (popup closed, no status item).
import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[2]) else {
    FileHandle.standardError.write(Data("usage: popup-probe.swift item|window|measure|period <pid> [n]\n".utf8))
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
case "diagnostic":
    var focus: CFTypeRef?, frontPID: pid_t = 0
    AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &focus)
    if let focus { AXUIElementGetPid(focus as! AXUIElement, &frontPID) }
    let window = popupWindow()
    print("front_pid=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? frontPID)\tpopup=\(window == nil ? 0 : 1)\twindow_id=\(window?.id ?? 0)\tactive=\(NSRunningApplication(processIdentifier: pid)?.isActive == true ? 1 : 0)")
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
case "period":
    guard args.count > 3, let index = Int(args[3]),
          let window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { fail("popup window is not open") }
    let titles = ["Today", "7 days", "30 days"]
    guard titles.indices.contains(index) else { fail("invalid period index") }
    let buttons = descendants(window).filter {
        attribute($0, kAXIdentifierAttribute) as? String == "period"
            && attribute($0, kAXRoleAttribute) as? String == kAXButtonRole
            && attribute($0, kAXDescriptionAttribute) as? String == titles[index]
    }
    guard let button = buttons.first else {
        for element in descendants(window) {
            let strings = [kAXIdentifierAttribute, kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute]
                .compactMap { attribute(element, $0) as? String }
            if strings.contains("period") || strings.contains(where: { ["Today", "7 days", "30 days"].contains($0) }) {
                FileHandle.standardError.write(Data("period candidate: \(strings.joined(separator: " | ")) frame=\(String(describing: rect(element)))\n".utf8))
            }
        }
        fail("no period button \(index), count \(buttons.count)")
    }
    exit(AXUIElementPerformAction(button, kAXPressAction as CFString) == .success ? 0 : 1)
case "tree":
    guard let window = popupWindow()?.element else { fail("popup window is not open") }
    for element in descendants(window) {
        let fields = [kAXRoleAttribute, kAXIdentifierAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute]
            .map { "\($0)=\((attribute(element, $0) as? String ?? "").replacingOccurrences(of: "\n", with: " / "))" }
        print(fields.joined(separator: "\t"), "frame=\(String(describing: rect(element)))")
    }
case "hour", "focus-hour", "hour-label":
    guard args.count > 3, let window = popupWindow()?.element,
          let cell = descendants(window).first(where: { attribute($0, kAXIdentifierAttribute) as? String == args[3] }) else {
        fail("hour cell is not accessible")
    }
    if args[1] == "hour" {
        guard let r = rect(cell) else { fail("hour cell has no frame") }
        print(Int(r.midX), Int(r.midY))
    } else if args[1] == "hour-label" {
        print([kAXDescriptionAttribute, kAXValueAttribute, kAXTitleAttribute].compactMap { attribute(cell, $0) as? String }.joined(separator: "\n"))
    } else {
        // Normal supported keyboard navigation, not a mutation of an AX attribute.
        // Custom focusable views accept Tab with macOS 14+ without changing global settings.
        let expected = (attribute(cell, kAXDescriptionAttribute) as? String) ?? ""
        guard !expected.isEmpty, let initial = popupWindow() else { fail("no focus target label") }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        for step in 1...200 {
            guard popupWindow()?.id == initial.id else { fail("popup closed during keyboard navigation") }
            CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)?.postToPid(pid)
            CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: false)?.postToPid(pid)
            usleep(70_000)
            if let detail = descendants(window).first(where: { attribute($0, kAXIdentifierAttribute) as? String == "hourDetail" }),
               ((attribute(detail, kAXValueAttribute) as? String) ?? (attribute(detail, kAXDescriptionAttribute) as? String)) == expected {
                FileHandle.standardError.write(Data("keyboard focus: \(step) local Tab events, unchanged window \(initial.id)\n".utf8))
                exit(0)
            }
        }
        fail("normal Tab navigation did not reach hour detail")
    }
case "hour-detail":
    guard let window = popupWindow()?.element,
          let detail = descendants(window).first(where: { attribute($0, kAXIdentifierAttribute) as? String == "hourDetail" }) else {
        fail("hour detail is not visible")
    }
    print((attribute(detail, kAXValueAttribute) as? String) ?? (attribute(detail, kAXDescriptionAttribute) as? String) ?? "")
default:
    fail("unknown command \(args[1])")
}
