// Accessibility and input helper for scripts/release-gate.py. Compiled by the gate; not part of the app.
// Usage: uihelper tree PID | press PID PATH | set PID PATH VALUE | focus PID PATH | move PID PATH X,Y
//        click X Y | windows PID | trusted
import ApplicationServices
import Foundation

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func point(_ e: AXUIElement, _ name: String) -> [Double]? {
    guard let raw = attr(e, name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    let v = raw as! AXValue
    if AXValueGetType(v) == .cgPoint { var p = CGPoint.zero; AXValueGetValue(v, .cgPoint, &p); return [p.x, p.y] }
    if AXValueGetType(v) == .cgSize { var s = CGSize.zero; AXValueGetValue(v, .cgSize, &s); return [s.width, s.height] }
    return nil
}

func text(_ value: AnyObject?) -> Any? {
    switch value {
    case let s as String: return s
    case let n as NSNumber: return n
    default: return nil
    }
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    var out = (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    if out.isEmpty, let windows = attr(e, kAXWindowsAttribute) as? [AXUIElement] { out = windows }
    return out
}

/// Depth-first nodes; `path` is the child-index chain from the application element.
func walk(_ e: AXUIElement, _ path: [Int], _ out: inout [[String: Any]], depth: Int = 0) {
    guard depth < 40 else { return }
    var node: [String: Any] = ["path": path.map(String.init).joined(separator: ".")]
    for (key, name) in [("role", kAXRoleAttribute), ("subrole", kAXSubroleAttribute), ("title", kAXTitleAttribute),
                        ("desc", kAXDescriptionAttribute), ("value", kAXValueAttribute), ("id", kAXIdentifierAttribute),
                        ("help", kAXHelpAttribute)] {
        if let v = text(attr(e, name)) { node[key] = v }
    }
    if let p = point(e, kAXPositionAttribute), let s = point(e, kAXSizeAttribute) { node["frame"] = p + s }
    if let focused = attr(e, kAXFocusedAttribute) as? Bool { node["focused"] = focused }
    var names: CFArray?
    if AXUIElementCopyActionNames(e, &names) == .success, let list = names as? [String], !list.isEmpty { node["actions"] = list }
    out.append(node)
    if node["role"] as? String == "AXMenu" { return }   // the main menu adds hundreds of nodes
    for (i, child) in children(e).enumerated() { walk(child, path + [i], &out, depth: depth + 1) }
}

func resolve(_ pid: pid_t, _ path: String) -> AXUIElement? {
    var e = AXUIElementCreateApplication(pid)
    for part in path.split(separator: ".") where !part.isEmpty {
        let list = children(e)
        guard let i = Int(part), i < list.count else { return nil }
        e = list[i]
    }
    return e
}

func emit(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data); print()
}

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: uihelper tree|press|set|focus|click|windows|trusted ...") }
switch args[1] {
case "trusted":
    print(AXIsProcessTrusted())
case "tree" where args.count == 3:
    var out: [[String: Any]] = []
    walk(AXUIElementCreateApplication(pid_t(args[2])!), [], &out)
    emit(out)
case "press" where args.count == 4:
    guard let e = resolve(pid_t(args[2])!, args[3]) else { fail("no element") }
    let r = AXUIElementPerformAction(e, kAXPressAction as CFString)
    if r != .success { fail("press failed \(r.rawValue)") }
case "set" where args.count == 5:
    guard let e = resolve(pid_t(args[2])!, args[3]) else { fail("no element") }
    let r = AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, args[4] as CFString)
    if r != .success { fail("set failed \(r.rawValue)") }
case "focus" where args.count == 4:
    guard let e = resolve(pid_t(args[2])!, args[3]) else { fail("no element") }
    let r = AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    if r != .success { fail("focus failed \(r.rawValue)") }
case "move" where args.count == 5:
    guard let e = resolve(pid_t(args[2])!, args[3]) else { fail("no element") }
    var p = CGPoint(x: Double(args[4].split(separator: ",")[0])!, y: Double(args[4].split(separator: ",")[1])!)
    let r = AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    if r != .success { fail("move failed \(r.rawValue)") }
case "click" where args.count == 4:
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(120_000)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
        e.setIntegerValueField(.mouseEventClickState, value: 1)
        e.post(tap: .cghidEventTap); usleep(80_000)
    }
case "windows" where args.count == 3:
    let pid = Int(args[2])!
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    emit(list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }.map { w -> [String: Any] in
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return ["id": w[kCGWindowNumber as String] ?? 0, "layer": w[kCGWindowLayer as String] ?? 0,
                "name": w[kCGWindowName as String] ?? "", "onscreen": w[kCGWindowIsOnscreen as String] ?? false,
                "frame": [b["X"] ?? 0, b["Y"] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0]]
    })
default:
    fail("bad arguments")
}
