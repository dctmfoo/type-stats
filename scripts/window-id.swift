// Prints the window id of the first on-screen window owned by a process name.
// Usage: swift scripts/window-id.swift TypeStats [pid]
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "TypeStats"
let pid = CommandLine.arguments.dropFirst(2).first.flatMap { Int($0) }
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w[kCGWindowOwnerName as String] as? String) == owner {
    if let pid, (w[kCGWindowOwnerPID as String] as? Int) != pid { continue }
    guard (w[kCGWindowLayer as String] as? Int) == 0, let id = w[kCGWindowNumber as String] as? Int else { continue }
    print(id)
    exit(0)
}
exit(1)
