import Cocoa
import CoreGraphics
import Combine

// MARK: - Mapping Model

enum MappingAction: String, Codable, CaseIterable {
    // Mouse buttons
    case mouseButton1 = "Left Click"
    case mouseButton2 = "Right Click"
    case mouseButton3 = "Middle Click"
    case mouseButton4 = "Mouse Button 4"
    case mouseButton5 = "Mouse Button 5"
    // Scroll
    case scrollUp = "Scroll Up"
    case scrollDown = "Scroll Down"
    case scrollLeft = "Scroll Left"
    case scrollRight = "Scroll Right"
    // Keyboard
    case keyPress = "Key Press"

    var isKeyPress: Bool { self == .keyPress }
}

struct KeyMapping: Codable, Identifiable {
    var id: UUID = UUID()

    // Trigger — the key combo the user holds
    var triggerKeyCode: UInt16        // CGKeyCode
    var triggerModifiers: UInt64      // CGEventFlags raw value

    // Action
    var action: MappingAction
    var actionKeyCode: UInt16?        // Only used when action == .keyPress
    var actionModifiers: UInt64?      // Only used when action == .keyPress
    var actionKeyLabel: String?       // Human readable label for action key

    // Human readable label for trigger
    var triggerLabel: String

    init(triggerKeyCode: UInt16, triggerModifiers: UInt64, triggerLabel: String,
         action: MappingAction, actionKeyCode: UInt16? = nil,
         actionModifiers: UInt64? = nil, actionKeyLabel: String? = nil) {
        self.triggerKeyCode = triggerKeyCode
        self.triggerModifiers = triggerModifiers
        self.triggerLabel = triggerLabel
        self.action = action
        self.actionKeyCode = actionKeyCode
        self.actionModifiers = actionModifiers
        self.actionKeyLabel = actionKeyLabel
    }
}

// MARK: - Settings Model

class ScrollSettings: ObservableObject {
    static let shared = ScrollSettings()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    @Published var speedMultiplier: Double {
        didSet { UserDefaults.standard.set(speedMultiplier, forKey: "speedMultiplier") }
    }
    @Published var invertVertical: Bool {
        didSet { UserDefaults.standard.set(invertVertical, forKey: "invertVertical") }
    }
    @Published var invertHorizontal: Bool {
        didSet { UserDefaults.standard.set(invertHorizontal, forKey: "invertHorizontal") }
    }
    @Published var smoothing: Bool {
        didSet { UserDefaults.standard.set(smoothing, forKey: "smoothing") }
    }
    @Published var blockedBundleIDs: [String] {
        didSet { UserDefaults.standard.set(blockedBundleIDs, forKey: "blockedBundleIDs") }
    }
    @Published var keyMappings: [KeyMapping] {
        didSet { saveMappings() }
    }

    init() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "isEnabled") == nil { ud.set(true, forKey: "isEnabled") }
        if ud.object(forKey: "speedMultiplier") == nil { ud.set(1.0, forKey: "speedMultiplier") }
        if ud.object(forKey: "smoothing") == nil { ud.set(true, forKey: "smoothing") }
        if ud.object(forKey: "blockedBundleIDs") == nil {
            ud.set([
                "com.blackmagic-design.DaVinciResolve",
                "com.blender.blender",
                "com.adobe.Photoshop",
                "com.adobe.illustrator",
                "com.adobe.AfterEffects",
                "com.autodesk.maya",
                "com.foundry.Nuke",
                "com.sidefx.houdini"
            ], forKey: "blockedBundleIDs")
        }
        self.isEnabled = ud.bool(forKey: "isEnabled")
        self.speedMultiplier = ud.double(forKey: "speedMultiplier")
        self.invertVertical = ud.bool(forKey: "invertVertical")
        self.invertHorizontal = ud.bool(forKey: "invertHorizontal")
        self.smoothing = ud.bool(forKey: "smoothing")
        self.blockedBundleIDs = ud.stringArray(forKey: "blockedBundleIDs") ?? []
        self.keyMappings = ScrollSettings.loadMappings()
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(keyMappings) {
            UserDefaults.standard.set(data, forKey: "keyMappings")
        }
    }

    private static func loadMappings() -> [KeyMapping] {
        guard let data = UserDefaults.standard.data(forKey: "keyMappings"),
              let mappings = try? JSONDecoder().decode([KeyMapping].self, from: data) else {
            return []
        }
        return mappings
    }
}

// MARK: - Scroll Engine

class ScrollEngine: ObservableObject {
    static let shared = ScrollEngine()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var middleButtonDown = false
    private var lastDragLocation = CGPoint.zero
    private var smoothVelocity = CGPoint.zero
    private var smoothingTimer: Timer?

    // Tracks which mapping triggers are currently held down
    private var activeMappingIDs: Set<UUID> = []

    let settings = ScrollSettings.shared

    @Published var hasAccessibilityPermission: Bool = false
    @Published var isRunning: Bool = false
    @Published var activeAppName: String = ""
    @Published var activeAppIsBlocked: Bool = false

    // MARK: - Start

    func start() {
        checkAccessibilityPermission()
        guard hasAccessibilityPermission else { return }
        installEventTap()
        startWatchingFrontmostApp()
    }

    func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.checkAccessibilityPermission()
            if self.hasAccessibilityPermission {
                timer.invalidate()
                self.installEventTap()
                self.startWatchingFrontmostApp()
            }
        }
    }

    // MARK: - Frontmost App

    private func startWatchingFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        updateActiveApp()
    }

    @objc private func frontmostAppChanged() { updateActiveApp() }

    private func updateActiveApp() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let app = NSWorkspace.shared.frontmostApplication
            let bundleID = app?.bundleIdentifier ?? ""
            self.activeAppName = app?.localizedName ?? ""
            self.activeAppIsBlocked = self.settings.blockedBundleIDs.contains(bundleID)
        }
    }

    func isCurrentAppBlocked() -> Bool {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return settings.blockedBundleIDs.contains(bundleID)
    }

    // MARK: - Blocklist Management

    func addCurrentAppToBlocklist() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              !settings.blockedBundleIDs.contains(bundleID) else { return }
        settings.blockedBundleIDs.append(bundleID)
        updateActiveApp()
    }

    func removeFromBlocklist(_ bundleID: String) {
        settings.blockedBundleIDs.removeAll { $0 == bundleID }
        updateActiveApp()
    }

    func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }

    // MARK: - Event Tap

    private func installEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << 26) | // OTD tablet button down/up
            (1 << 27)   // OTD tablet pointer move
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[StylusScroll] Failed to create event tap")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    func stopEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // DEBUG — remove after diagnosis
        if type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged {
            let btn = event.getIntegerValueField(.mouseEventButtonNumber)
            print("[StylusScroll] \(type) button=\(btn)")
        }

        guard settings.isEnabled, !isCurrentAppBlocked() else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event: event)
        case .keyUp:
            return handleKeyUp(event: event)
        default:
            break
        }

        // Middle-click scroll handling
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        // OTD on macOS sends tablet events as raw types 26 (button) and 27 (move)
        // Standard drivers send otherMouseDown/Up/Dragged with buttonNumber == 2
        let isOTDButton = type == CGEventType(rawValue: 26)
        let isOTDMove   = type == CGEventType(rawValue: 27)
        let isStandard  = type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged

        guard isOTDButton || isOTDMove || (isStandard && buttonNumber == 2) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .otherMouseDown:
            middleButtonDown = true
            lastDragLocation = event.location
            smoothVelocity = .zero
            return nil

        case CGEventType(rawValue: 26) where !middleButtonDown:
            // OTD tablet button press
            middleButtonDown = true
            lastDragLocation = event.location
            smoothVelocity = .zero
            return nil

        case .otherMouseUp:
            guard middleButtonDown else { break }
            middleButtonDown = false
            if settings.smoothing { startMomentumScroll() }
            return nil

        case CGEventType(rawValue: 26) where middleButtonDown:
            // OTD tablet button release
            middleButtonDown = false
            if settings.smoothing { startMomentumScroll() }
            return nil

        case .otherMouseDragged, CGEventType(rawValue: 27):
            guard middleButtonDown else { break }
            let current = event.location
            let rawDX = current.x - lastDragLocation.x
            let rawDY = current.y - lastDragLocation.y
            lastDragLocation = current

            let speed = settings.speedMultiplier
            let dX = rawDX * speed * (settings.invertHorizontal ? 1.0 : -1.0)
            let dY = rawDY * speed * (settings.invertVertical ? 1.0 : -1.0)

            if settings.smoothing {
                smoothVelocity.x = smoothVelocity.x * 0.6 + dX * 0.4
                smoothVelocity.y = smoothVelocity.y * 0.6 + dY * 0.4
                postScrollEvent(dx: smoothVelocity.x, dy: smoothVelocity.y, at: current)
            } else {
                postScrollEvent(dx: dX, dy: dY, at: current)
            }
            return nil

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Key Mapping Handling

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        for mapping in settings.keyMappings {
            guard mapping.triggerKeyCode == keyCode else { continue }
            let mappingMods = CGEventFlags(rawValue: mapping.triggerModifiers)
            guard eventModifiersMatch(event.flags, expected: mappingMods) else { continue }

            // Consume the key event and fire the mapped action
            if !activeMappingIDs.contains(mapping.id) {
                activeMappingIDs.insert(mapping.id)
                fireMappingAction(mapping, isDown: true, at: event.location)
            }
            return nil // Consume original key event
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        for mapping in settings.keyMappings {
            guard mapping.triggerKeyCode == keyCode else { continue }
            if activeMappingIDs.contains(mapping.id) {
                activeMappingIDs.remove(mapping.id)
                fireMappingAction(mapping, isDown: false, at: event.location)
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func eventModifiersMatch(_ actual: CGEventFlags, expected: CGEventFlags) -> Bool {
        // Check only the meaningful modifier bits
        let mask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return actual.intersection(mask) == expected.intersection(mask)
    }

    private func fireMappingAction(_ mapping: KeyMapping, isDown: Bool, at location: CGPoint) {
        switch mapping.action {
        case .mouseButton1:
            postMouseEvent(button: 0, type: isDown ? .leftMouseDown : .leftMouseUp, at: location)
        case .mouseButton2:
            postMouseEvent(button: 1, type: isDown ? .rightMouseDown : .rightMouseUp, at: location)
        case .mouseButton3:
            postMouseEvent(button: 2, type: isDown ? .otherMouseDown : .otherMouseUp, at: location)
        case .mouseButton4:
            postMouseEvent(button: 3, type: isDown ? .otherMouseDown : .otherMouseUp, at: location)
        case .mouseButton5:
            postMouseEvent(button: 4, type: isDown ? .otherMouseDown : .otherMouseUp, at: location)
        case .scrollUp:
            if isDown { postScrollEvent(dx: 0, dy: 20, at: location) }
        case .scrollDown:
            if isDown { postScrollEvent(dx: 0, dy: -20, at: location) }
        case .scrollLeft:
            if isDown { postScrollEvent(dx: -20, dy: 0, at: location) }
        case .scrollRight:
            if isDown { postScrollEvent(dx: 20, dy: 0, at: location) }
        case .keyPress:
            if let keyCode = mapping.actionKeyCode {
                let mods = CGEventFlags(rawValue: mapping.actionModifiers ?? 0)
                if isDown {
                    postSystemAction(keyCode: keyCode, modifiers: mods)
                }
            }
        }
    }

    // MARK: - Event Injection

    private func postMouseEvent(button: Int, type: CGEventType, at location: CGPoint) {
        let mouseButton: CGMouseButton = button == 0 ? .left : button == 1 ? .right : .center
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: location, mouseButton: mouseButton) else { return }
        if button > 2 {
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        }
        event.post(tap: .cgSessionEventTap)
    }

    private func postScrollEvent(dx: CGFloat, dy: CGFloat, at location: CGPoint) {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0
        ) else { return }
        if location != .zero {
            scrollEvent.location = location
        }
        scrollEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        scrollEvent.post(tap: .cgSessionEventTap)
    }

    private func postKeyEvent(keyCode: UInt16, modifiers: CGEventFlags, isDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { return }
        event.flags = modifiers
        event.post(tap: .cghidEventTap)
    }
    
    private func postSystemAction(keyCode: UInt16, modifiers: CGEventFlags) {
        let isShowDesktop = keyCode == 0x67
        let isControlUp   = keyCode == 0x7E && modifiers.contains(.maskControl)
        let isControlDown = keyCode == 0x7D && modifiers.contains(.maskControl)

        if isShowDesktop {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments  = ["-e", "tell application \"System Events\" to key code 103"]
            try? task.run()
            return
        }

        if isControlUp {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments  = ["-e", "tell application \"System Events\" to key code 126 using control down"]
            try? task.run()
            return
        }

        if isControlDown {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments  = ["-e", "tell application \"System Events\" to key code 125 using control down"]
            try? task.run()
            return
        }

        // Normal key for everything else
        postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)
        postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)
    }

    // MARK: - Momentum

    private func startMomentumScroll() {
        smoothingTimer?.invalidate()
        var velocity = smoothVelocity
        guard abs(velocity.x) > 0.5 || abs(velocity.y) > 0.5 else { return }

        smoothingTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            velocity.x *= 0.88
            velocity.y *= 0.88
            if abs(velocity.x) < 0.3 && abs(velocity.y) < 0.3 { timer.invalidate(); return }
            self.postScrollEvent(dx: velocity.x, dy: velocity.y, at: .zero)
        }
    }
}

// MARK: - C Callback

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType,
    event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = engine.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    return engine.handleEvent(type: type, event: event)
}

// MARK: - Helpers

extension NSPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
