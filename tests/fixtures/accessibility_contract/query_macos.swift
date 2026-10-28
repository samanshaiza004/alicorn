import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

let defaultTitle = "Alicorn Accessibility Contract"
let arguments = CommandLine.arguments
let title = arguments.count > 1 ? arguments[1] : defaultTitle
let probeValue = "AX contract value"

func fail(_ message: String) -> Never {
    fputs("accessibility-contract: FAIL: \(message)\n", stderr)
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var result: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name, &result)
    guard error == .success else { return nil }
    return result
}

func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    if let value = attribute(element, name) as? String { return value }
    return nil
}

func children(of element: AXUIElement) -> [AXUIElement] {
    guard let value = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else { return [] }
    return value
}

func descendants(of root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 20 else { return [] }
    var result: [AXUIElement] = []
    for child in children(of: root) {
        result.append(child)
        result.append(contentsOf: descendants(of: child, depth: depth + 1))
    }
    return result
}

func point(_ value: AnyObject?) -> CGPoint? {
    guard let value = value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var result = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &result) else { return nil }
    return result
}

func size(_ value: AnyObject?) -> CGSize? {
    guard let value = value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var result = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &result) else { return nil }
    return result
}

func printableValue(_ element: AXUIElement) -> String? {
    guard let value = attribute(element, kAXValueAttribute as CFString) else { return nil }
    if let string = value as? String { return string }
    return String(describing: value)
}

func named(_ element: AXUIElement, _ expected: String) -> Bool {
    return stringAttribute(element, kAXTitleAttribute as CFString) == expected ||
        stringAttribute(element, kAXDescriptionAttribute as CFString) == expected ||
        stringAttribute(element, kAXIdentifierAttribute as CFString) == expected
}

func elements(in root: AXUIElement) -> [AXUIElement] {
    return [root] + descendants(of: root)
}

func findElement(in root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    return elements(in: root).first(where: predicate)
}

func enabled(_ element: AXUIElement) -> Bool? {
    guard let value = attribute(element, kAXEnabledAttribute as CFString) else { return nil }
    return (value as? NSNumber)?.boolValue
}

func boundsEvidence(_ label: String, _ element: AXUIElement) -> [String: Any] {
    let (position, dimensions) = bounds(element)
    return [
        "kind": label,
        "role": stringAttribute(element, kAXRoleAttribute as CFString) ?? "",
        "name": stringAttribute(element, kAXTitleAttribute as CFString) ?? stringAttribute(element, kAXDescriptionAttribute as CFString) ?? "",
        "bounds": ["x": position.x, "y": position.y, "width": dimensions.width, "height": dimensions.height],
    ]
}

func findNamedButton(_ name: String, in root: AXUIElement) -> AXUIElement? {
    return findElement(in: root) {
        stringAttribute($0, kAXRoleAttribute as CFString) == (kAXButtonRole as String) && named($0, name)
    }
}

func findNamedField(in root: AXUIElement) -> AXUIElement? {
    return findElement(in: root) {
        let role = stringAttribute($0, kAXRoleAttribute as CFString)
        return (role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)) &&
            named($0, "Contract text field")
    }
}

func waitForEnabled(_ expected: Bool, name: String, in root: AXUIElement) -> AXUIElement {
    let deadline = Date().addingTimeInterval(3)
    var lastState = "unavailable"
    while Date() < deadline {
        if let element = findNamedButton(name, in: root) {
            if let current = enabled(element) {
                lastState = String(current)
                if current == expected { return element }
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    fail("AX element '\(name)' did not report AXEnabled=\(expected) within 3 seconds (last state: \(lastState)).")
}

func pressNamedButton(_ name: String, in root: AXUIElement) {
    guard let element = findNamedButton(name, in: root) else {
        fail("AX button '\(name)' disappeared from the accessibility tree.")
    }
    let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard error == .success else {
        fail("AXPress failed for '\(name)' (error \(error.rawValue)).")
    }
}

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    fail("Terminal/Swift lacks macOS Accessibility permission. Enable it in System Settings → Privacy & Security → Accessibility, then rerun.")
}

var targetWindow: AXUIElement?
for application in NSWorkspace.shared.runningApplications where application.processIdentifier > 0 {
    if application.processIdentifier == ProcessInfo.processInfo.processIdentifier { continue }
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    let appWindows = attribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? children(of: appElement)
    for window in appWindows where stringAttribute(window, kAXRoleAttribute as CFString) == (kAXWindowRole as String) {
        if stringAttribute(window, kAXTitleAttribute as CFString) == title {
            targetWindow = window
            break
        }
    }
    if targetWindow != nil { break }
}
guard let window = targetWindow else {
    fail("Window '\(title)' not found. Start tests/fixtures/accessibility_contract/run.sh first; pass another title as the first argument if needed.")
}

let allElements = [window] + descendants(of: window)
guard let button = allElements.first(where: { stringAttribute($0, kAXRoleAttribute as CFString) == (kAXButtonRole as String) && named($0, "Increment value") }) else {
    fail("Named button was not exposed with AXButton role and title 'Increment value'.")
}
guard let toggle = allElements.first(where: { stringAttribute($0, kAXRoleAttribute as CFString) == (kAXButtonRole as String) && named($0, "Toggle action disabled") }) else {
    fail("Named disabled-state toggle was not exposed with AXButton role and title 'Toggle action disabled'.")
}
guard let guarded = allElements.first(where: { stringAttribute($0, kAXRoleAttribute as CFString) == (kAXButtonRole as String) && named($0, "Guarded action") }) else {
    fail("Named guarded action was not exposed with AXButton role and title 'Guarded action'.")
}
guard let field = allElements.first(where: {
    let role = stringAttribute($0, kAXRoleAttribute as CFString)
    return (role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)) && named($0, "Contract text field")
}) else {
    fail("Named editable field was not exposed with AXTextField/AXTextArea role and title 'Contract text field'.")
}
guard let status = allElements.first(where: { named($0, "Action count") }) else {
    fail("Named action status 'Action count' was not exposed in the AX tree.")
}
guard let statusRole = stringAttribute(status, kAXRoleAttribute as CFString), !statusRole.isEmpty else {
    fail("Action status did not expose an AX role.")
}

func bounds(_ element: AXUIElement) -> (CGPoint, CGSize) {
    guard let position = point(attribute(element, kAXPositionAttribute as CFString)),
          let size = size(attribute(element, kAXSizeAttribute as CFString)),
          size.width > 0, size.height > 0 else {
        fail("Element has missing or empty AXPosition/AXSize bounds.")
    }
    return (position, size)
}

func record(_ label: String, _ element: AXUIElement) -> [String: Any] {
    let (position, dimensions) = bounds(element)
    return [
        "kind": label,
        "role": stringAttribute(element, kAXRoleAttribute as CFString) ?? "",
        "name": stringAttribute(element, kAXTitleAttribute as CFString) ?? stringAttribute(element, kAXDescriptionAttribute as CFString) ?? "",
        "value": printableValue(element) ?? NSNull(),
        "focused": (attribute(element, kAXFocusedAttribute as CFString) as? Bool) ?? false,
        "enabled": enabled(element) ?? false,
        "bounds": ["x": position.x, "y": position.y, "width": dimensions.width, "height": dimensions.height],
    ]
}

let trackedBeforeResize: [(String, AXUIElement)] = [
    ("button", button),
    ("field", field),
    ("status", status),
    ("toggle", toggle),
    ("guarded", guarded),
]
let controlsBeforeResize = trackedBeforeResize.map { boundsEvidence($0.0, $0.1) }
let (windowPositionBefore, windowSizeBefore) = bounds(window)
let fieldWidthBefore = bounds(field).1.width
var sizeSettable = DarwinBoolean(false)
let settableError = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable)
guard settableError == .success else {
    fail("Could not query whether AXSize is settable on the fixture window (error \(settableError.rawValue)).")
}
guard sizeSettable.boolValue else {
    fail("Fixture window reports AXSize as read-only; native accessibility resizing is unavailable.")
}
var requestedWindowSize = CGSize(width: windowSizeBefore.width + 240, height: windowSizeBefore.height + 140)
guard let requestedSizeValue = AXValueCreate(.cgSize, &requestedWindowSize) else {
    fail("Could not create AXValue for requested window size.")
}
let resizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, requestedSizeValue)
guard resizeError == .success else {
    fail("AX could not resize the fixture window from \(windowSizeBefore.width)x\(windowSizeBefore.height) to \(requestedWindowSize.width)x\(requestedWindowSize.height) (error \(resizeError.rawValue)).")
}

let resizeDeadline = Date().addingTimeInterval(5)
var windowSizeAfter: CGSize?
var controlsAfterResize: [(String, AXUIElement)]?
while Date() < resizeDeadline {
    if let currentWindowSize = size(attribute(window, kAXSizeAttribute as CFString)),
       let currentField = findElement(in: window, matching: {
           let role = stringAttribute($0, kAXRoleAttribute as CFString)
           return (role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)) && named($0, "Contract text field")
       }),
       let currentFieldSize = size(attribute(currentField, kAXSizeAttribute as CFString)),
       currentWindowSize.width >= windowSizeBefore.width + 120,
       currentFieldSize.width >= fieldWidthBefore + 100 {
        windowSizeAfter = currentWindowSize
        guard let currentButton = findNamedButton("Increment value", in: window),
              let currentToggle = findNamedButton("Toggle action disabled", in: window),
              let currentGuarded = findNamedButton("Guarded action", in: window),
              let currentStatus = findElement(in: window, matching: { named($0, "Action count") }) else {
            fail("One or more named controls disappeared after the native window resize.")
        }
        controlsAfterResize = [
            ("button", currentButton),
            ("field", currentField),
            ("status", currentStatus),
            ("toggle", currentToggle),
            ("guarded", currentGuarded),
        ]
        break
    }
    Thread.sleep(forTimeInterval: 0.1)
}
guard let finalWindowSize = windowSizeAfter, let finalControls = controlsAfterResize else {
    let lastWindowSize = size(attribute(window, kAXSizeAttribute as CFString))
    let lastField = findElement(in: window, matching: {
        let role = stringAttribute($0, kAXRoleAttribute as CFString)
        return (role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)) && named($0, "Contract text field")
    })
    let lastFieldWidth = lastField.flatMap { size(attribute($0, kAXSizeAttribute as CFString))?.width }
    fail("Native AX resize did not publish dynamic field bounds within 5 seconds (window width \(lastWindowSize?.width.description ?? "unavailable"), field width \(lastFieldWidth?.description ?? "unavailable")).")
}
let controlsAfterRecords = finalControls.map { boundsEvidence($0.0, $0.1) }
guard let measuredResizedField = finalControls.first(where: { $0.0 == "field" })?.1 else {
    fail("Editable field disappeared from the post-resize bounds evidence.")
}
let fieldWidthAfter = bounds(measuredResizedField).1.width
guard fieldWidthAfter >= fieldWidthBefore + 100 else {
    fail("Resizing the window did not expand the AX text field bounds by at least 100 points (before \(fieldWidthBefore), after \(fieldWidthAfter)).")
}
var changedControls: [String] = []
for before in controlsBeforeResize {
    guard let after = controlsAfterRecords.first(where: { ($0["kind"] as? String) == (before["kind"] as? String) }),
          let beforeRect = before["bounds"] as? [String: CGFloat],
          let afterRect = after["bounds"] as? [String: CGFloat] else { continue }
    if ["x", "y", "width", "height"].contains(where: { key in
        guard let old = beforeRect[key], let new = afterRect[key] else { return false }
        return abs(new - old) > 1
    }), let kind = before["kind"] as? String {
        changedControls.append(kind)
    }
}
guard changedControls.contains("field") else {
    fail("No dynamic native control bounds changed after the AX window resize.")
}
let resizeEvidence: [String: Any] = [
    "method": "AXUIElementSetAttributeValue(AXSize)",
    "windowBefore": ["x": windowPositionBefore.x, "y": windowPositionBefore.y, "width": windowSizeBefore.width, "height": windowSizeBefore.height],
    "windowAfter": ["width": finalWindowSize.width, "height": finalWindowSize.height],
    "requested": ["width": requestedWindowSize.width, "height": requestedWindowSize.height],
    "controlsBefore": controlsBeforeResize,
    "controlsAfter": controlsAfterRecords,
    "changedControls": changedControls,
]

guard let resizedButton = finalControls.first(where: { $0.0 == "button" })?.1,
      let resizedField = finalControls.first(where: { $0.0 == "field" })?.1,
      let resizedStatus = finalControls.first(where: { $0.0 == "status" })?.1,
      let resizedGuarded = finalControls.first(where: { $0.0 == "guarded" })?.1 else {
    fail("One or more named controls were missing from the refreshed post-resize AX tree.")
}

let initialFieldValue = printableValue(resizedField) ?? ""
guard initialFieldValue == "Editable value" else {
    fail("Unexpected initial field value '\(initialFieldValue)'; expected 'Editable value'.")
}
let initialStatusValue = printableValue(resizedStatus) ?? ""
guard initialStatusValue == "0" else {
    fail("Unexpected initial status value '\(initialStatusValue)'; expected '0'.")
}

let focusError = AXUIElementSetAttributeValue(resizedField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
guard focusError == .success else { fail("Could not focus the editable field through AX (error \(focusError.rawValue)).") }
Thread.sleep(forTimeInterval: 0.25)
guard (attribute(resizedField, kAXFocusedAttribute as CFString) as? Bool) == true else {
    fail("Editable field did not report AXFocused=true after focus request.")
}

let setValueError = AXUIElementSetAttributeValue(resizedField, kAXValueAttribute as CFString, probeValue as CFString)
guard setValueError == .success else { fail("AX could not set the editable value (error \(setValueError.rawValue)).") }
let valueDeadline = Date().addingTimeInterval(3)
var fieldAfterValue = resizedField
var observedFieldValue = printableValue(fieldAfterValue) ?? ""
while Date() < valueDeadline && observedFieldValue != probeValue {
    if let refreshedField = findNamedField(in: window) {
        fieldAfterValue = refreshedField
        observedFieldValue = printableValue(refreshedField) ?? ""
    }
    if observedFieldValue != probeValue { Thread.sleep(forTimeInterval: 0.1) }
}
guard observedFieldValue == probeValue else {
    fail("AX SetValue did not update the exposed field value (last observed '\(observedFieldValue)').")
}

let beforeStatus = printableValue(resizedStatus) ?? stringAttribute(resizedStatus, kAXTitleAttribute as CFString) ?? ""
let pressError = AXUIElementPerformAction(resizedButton, kAXPressAction as CFString)
guard pressError == .success else { fail("AXPress failed for the named button (error \(pressError.rawValue)).") }
let statusDeadline = Date().addingTimeInterval(3)
var afterStatus = beforeStatus
while Date() < statusDeadline {
    let currentStatus = findElement(in: window, matching: { named($0, "Action count") }) ?? resizedStatus
    afterStatus = printableValue(currentStatus) ?? stringAttribute(currentStatus, kAXTitleAttribute as CFString) ?? ""
    if afterStatus != beforeStatus { break }
    Thread.sleep(forTimeInterval: 0.1)
}
guard afterStatus != beforeStatus else { fail("AXPress did not change the exposed status value '\(beforeStatus)'.") }
guard afterStatus == "1" else { fail("AXPress produced status value '\(afterStatus)'; expected '1'.") }

guard let guardedEnabledBefore = enabled(resizedGuarded), guardedEnabledBefore else {
    fail("Guarded action did not initially report AXEnabled=true.")
}
pressNamedButton("Toggle action disabled", in: window)
let guardedAfterDisableElement = waitForEnabled(false, name: "Guarded action", in: window)
guard let guardedEnabledAfterDisable = enabled(guardedAfterDisableElement), !guardedEnabledAfterDisable else {
    fail("Guarded action did not report AXEnabled=false after the toggle action.")
}
pressNamedButton("Toggle action disabled", in: window)
let guardedAfterReenableElement = waitForEnabled(true, name: "Guarded action", in: window)
guard let guardedEnabledAfterReenable = enabled(guardedAfterReenableElement), guardedEnabledAfterReenable else {
    fail("Guarded action did not report AXEnabled=true after being re-enabled.")
}
guard let finalToggle = findNamedButton("Toggle action disabled", in: window) else {
    fail("Disabled-state toggle disappeared before final evidence capture.")
}

let report: [String: Any] = [
    "result": "PASS",
    "window": title,
    "elements": [
        record("button", resizedButton),
        record("field", fieldAfterValue),
        record("status", resizedStatus),
        record("toggle", finalToggle),
        record("guarded", guardedAfterReenableElement),
    ],
    "resize": resizeEvidence,
    "guardedAction": [
        "name": "Guarded action",
        "role": stringAttribute(guardedAfterReenableElement, kAXRoleAttribute as CFString) ?? "",
        "enabledStates": [guardedEnabledBefore, guardedEnabledAfterDisable, guardedEnabledAfterReenable],
        "toggleAction": "AXPress",
    ],
    "fieldValueBefore": initialFieldValue,
    "fieldValueAfter": printableValue(fieldAfterValue) ?? "",
    "fieldFocused": (attribute(fieldAfterValue, kAXFocusedAttribute as CFString) as? Bool) ?? false,
    "statusBefore": beforeStatus,
    "statusAfter": afterStatus,
    "action": "AXPress",
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0a]))
