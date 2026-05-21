import SwiftUI
import ServiceManagement
import Carbon

// MARK: - Menu Bar Popover

struct MenuBarView: View {
    @EnvironmentObject var engine: ScrollEngine
    @ObservedObject var settings = ScrollSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "hand.draw.fill").foregroundColor(.accentColor)
                Text("StylusScroll").font(.headline)
                Spacer()
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusLabel).font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            if !engine.hasAccessibilityPermission {
                AccessibilityBanner().environmentObject(engine)
                Divider()
            }

            if engine.isRunning && !engine.activeAppName.isEmpty {
                ActiveAppBanner().environmentObject(engine)
                Divider()
            }

            VStack(spacing: 12) {
                Toggle("Enable StylusScroll", isOn: $settings.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                HStack {
                    Text("Speed").foregroundColor(.secondary).font(.subheadline)
                    Spacer()
                    Slider(value: $settings.speedMultiplier, in: 0.2...3.0, step: 0.1)
                        .frame(width: 120)
                    Text(String(format: "%.1f×", settings.speedMultiplier))
                        .font(.subheadline).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                Toggle("Momentum scrolling", isOn: $settings.smoothing)
                    .font(.subheadline).toggleStyle(SwitchToggleStyle(tint: .accentColor))
                Toggle("Invert vertical", isOn: $settings.invertVertical)
                    .font(.subheadline).toggleStyle(SwitchToggleStyle(tint: .accentColor))
                Toggle("Invert horizontal", isOn: $settings.invertHorizontal)
                    .font(.subheadline).toggleStyle(SwitchToggleStyle(tint: .accentColor))

                LaunchAtLoginToggle()
            }
            .padding(16)

            Divider()

            HStack {
                Button("Quit") { NSApp.terminate(nil) }.foregroundColor(.secondary)
                Spacer()
                SettingsLink { Text("Open Settings") }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .font(.subheadline).buttonStyle(.plain)
        }
    }

    private var statusColor: Color {
        if !engine.isRunning || !settings.isEnabled { return Color.gray.opacity(0.4) }
        if engine.activeAppIsBlocked { return Color.orange }
        return Color.green
    }
    private var statusLabel: String {
        if !engine.isRunning || !settings.isEnabled { return "Inactive" }
        if engine.activeAppIsBlocked { return "Paused" }
        return "Active"
    }
}

// MARK: - Active App Banner

struct ActiveAppBanner: View {
    @EnvironmentObject var engine: ScrollEngine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.activeAppIsBlocked ? "pause.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(engine.activeAppIsBlocked ? .orange : .green)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.activeAppName).font(.subheadline).fontWeight(.medium)
                Text(engine.activeAppIsBlocked ? "StylusScroll paused" : "StylusScroll active")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if engine.activeAppIsBlocked {
                Button("Unblock") {
                    if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                        engine.removeFromBlocklist(id)
                    }
                }.buttonStyle(.borderedProminent).controlSize(.small).tint(.green)
            } else {
                Button("Block") { engine.addCurrentAppToBlocklist() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Accessibility Banner

struct AccessibilityBanner: View {
    @EnvironmentObject var engine: ScrollEngine
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access needed").font(.subheadline).fontWeight(.medium)
                Text("Required to intercept stylus events").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Grant") { engine.requestAccessibilityPermission() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Launch at Login

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin: Bool = false
    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .font(.subheadline).toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .onAppear {
                if #available(macOS 13.0, *) { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
            }
            .onChange(of: launchAtLogin) { _, enabled in
                if #available(macOS 13.0, *) {
                    try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            }
    }
}

// MARK: - Settings Window

struct SettingsView: View {
    @EnvironmentObject var engine: ScrollEngine
    @ObservedObject var settings = ScrollSettings.shared
    @State private var selectedTab = "scroll"

    var body: some View {
        TabView(selection: $selectedTab) {
            ScrollSettingsTab().tag("scroll").tabItem { Label("Scrolling", systemImage: "scroll") }
            MappingsTab().tag("mappings").tabItem { Label("Key Mappings", systemImage: "keyboard") }
            AppBlocklistTab().environmentObject(engine).tag("apps").tabItem { Label("App Blocklist", systemImage: "app.badge") }
            SystemTab().environmentObject(engine).tag("system").tabItem { Label("System", systemImage: "gear") }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - Scroll Settings Tab

struct ScrollSettingsTab: View {
    @ObservedObject var settings = ScrollSettings.shared
    var body: some View {
        Form {
            Section("Behaviour") {
                Toggle("Enable StylusScroll", isOn: $settings.isEnabled)
                HStack {
                    Text("Scroll speed")
                    Spacer()
                    Slider(value: $settings.speedMultiplier, in: 0.2...3.0, step: 0.1).frame(width: 160)
                    Text(String(format: "%.1f×", settings.speedMultiplier)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Toggle("Momentum (coast after release)", isOn: $settings.smoothing)
            }
            Section("Direction") {
                Toggle("Invert vertical scroll", isOn: $settings.invertVertical)
                Toggle("Invert horizontal scroll", isOn: $settings.invertHorizontal)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Key Mappings Tab

struct MappingsTab: View {
    @ObservedObject var settings = ScrollSettings.shared
    @State private var showingAddSheet = false
    @State private var editingMapping: KeyMapping? = nil

    var body: some View {
        VStack(spacing: 0) {
            if settings.keyMappings.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "keyboard").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("No mappings yet").font(.headline)
                    Text("Add a mapping to trigger mouse buttons,\nscroll events, or key presses from any key combo.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("Add Mapping") { showingAddSheet = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List {
                    ForEach(settings.keyMappings) { mapping in
                        HStack {
                            MappingRow(mapping: mapping)
                                .contentShape(Rectangle())
                                .onTapGesture { editingMapping = mapping }
                            Button {
                                settings.keyMappings.removeAll { $0.id == mapping.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                        }
                    }
                }

                Divider()

                HStack {
                    Text("\(settings.keyMappings.count) mapping\(settings.keyMappings.count == 1 ? "" : "s")")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Add Mapping") { showingAddSheet = true }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            MappingEditorSheet(existingMapping: nil) { newMapping in
                settings.keyMappings.append(newMapping)
            }
        }
        .sheet(item: $editingMapping) { mapping in
            MappingEditorSheet(existingMapping: mapping) { updated in
                if let idx = settings.keyMappings.firstIndex(where: { $0.id == updated.id }) {
                    settings.keyMappings[idx] = updated
                }
            }
        }
    }
}

// MARK: - Mapping Row

struct MappingRow: View {
    let mapping: KeyMapping
    var body: some View {
        HStack(spacing: 12) {
            // Trigger
            VStack(alignment: .leading, spacing: 2) {
                Text("When").font(.caption).foregroundColor(.secondary)
                Text(mapping.triggerLabel)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
            }
            Image(systemName: "arrow.right").foregroundColor(.secondary)
            // Action
            VStack(alignment: .leading, spacing: 2) {
                Text("Do").font(.caption).foregroundColor(.secondary)
                Text(actionLabel)
                    .font(.subheadline)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var actionLabel: String {
        if mapping.action == .keyPress, let label = mapping.actionKeyLabel {
            return "Key: \(label)"
        }
        return mapping.action.rawValue
    }
}

// MARK: - Mapping Editor Sheet

struct MappingEditorSheet: View {
    let existingMapping: KeyMapping?
    let onSave: (KeyMapping) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var isRecordingTrigger = false
    @State private var triggerKeyCode: UInt16 = 0
    @State private var triggerModifiers: UInt64 = 0
    @State private var triggerLabel: String = ""
    @State private var selectedAction: MappingAction = .mouseButton4
    @State private var isRecordingActionKey = false
    @State private var actionKeyCode: UInt16 = 0
    @State private var actionModifiers: UInt64 = 0
    @State private var actionKeyLabel: String = ""
    @State private var keyRecorder: KeyRecorderHelper? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(existingMapping == nil ? "Add Mapping" : "Edit Mapping")
                .font(.headline).padding(.top, 4)

            // Trigger section
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger key combo").font(.subheadline).foregroundColor(.secondary)
                HStack {
                    Text(triggerLabel.isEmpty ? "Click to record..." : triggerLabel)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(isRecordingTrigger ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingTrigger ? Color.accentColor : Color.clear, lineWidth: 1.5))
                        .cornerRadius(8)
                        .onTapGesture { startRecordingTrigger() }

                    if !triggerLabel.isEmpty {
                        Button { triggerLabel = ""; triggerKeyCode = 0; triggerModifiers = 0 } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                if isRecordingTrigger {
                    Text("Press any key combo now...").font(.caption).foregroundColor(.accentColor)
                }
            }

            // Action section
            VStack(alignment: .leading, spacing: 8) {
                Text("Action").font(.subheadline).foregroundColor(.secondary)
                Picker("Action", selection: $selectedAction) {
                    Section("Mouse Buttons") {
                        ForEach([MappingAction.mouseButton1, .mouseButton2, .mouseButton3, .mouseButton4, .mouseButton5], id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Section("Scroll") {
                        ForEach([MappingAction.scrollUp, .scrollDown, .scrollLeft, .scrollRight], id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Section("Keyboard") {
                        Text("Key Press").tag(MappingAction.keyPress)
                    }
                }
                .pickerStyle(.menu).labelsHidden()

                // Key press recorder — only shown when action is keyPress
                if selectedAction == .keyPress {
                    HStack {
                        Text(actionKeyLabel.isEmpty ? "Click to record key..." : actionKeyLabel)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(isRecordingActionKey ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingActionKey ? Color.accentColor : Color.clear, lineWidth: 1.5))
                            .cornerRadius(8)
                            .onTapGesture { startRecordingActionKey() }

                        if !actionKeyLabel.isEmpty {
                            Button { actionKeyLabel = ""; actionKeyCode = 0; actionModifiers = 0 } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    if isRecordingActionKey {
                        Text("Press the key combo to send...").font(.caption).foregroundColor(.accentColor)
                    }
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var mapping = KeyMapping(
                        triggerKeyCode: triggerKeyCode,
                        triggerModifiers: triggerModifiers,
                        triggerLabel: triggerLabel,
                        action: selectedAction,
                        actionKeyCode: selectedAction == .keyPress ? actionKeyCode : nil,
                        actionModifiers: selectedAction == .keyPress ? actionModifiers : nil,
                        actionKeyLabel: selectedAction == .keyPress ? actionKeyLabel : nil
                    )
                    // Preserve the original ID if editing so the update finds the right row
                    if let existing = existingMapping {
                        mapping.id = existing.id
                    }
                    onSave(mapping)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(triggerLabel.isEmpty || (selectedAction == .keyPress && actionKeyLabel.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 420, height: 380)
        .onAppear { loadExisting() }
    }

    private func loadExisting() {
        guard let m = existingMapping else { return }
        triggerKeyCode = m.triggerKeyCode
        triggerModifiers = m.triggerModifiers
        triggerLabel = m.triggerLabel
        selectedAction = m.action
        actionKeyCode = m.actionKeyCode ?? 0
        actionModifiers = m.actionModifiers ?? 0
        actionKeyLabel = m.actionKeyLabel ?? ""
    }

    private func startRecordingTrigger() {
        isRecordingTrigger = true
        isRecordingActionKey = false
        keyRecorder = KeyRecorderHelper { keyCode, modifiers, label in
            self.triggerKeyCode = keyCode
            self.triggerModifiers = modifiers
            self.triggerLabel = label
            self.isRecordingTrigger = false
            self.keyRecorder = nil
        }
    }

    private func startRecordingActionKey() {
        isRecordingActionKey = true
        isRecordingTrigger = false
        keyRecorder = KeyRecorderHelper { keyCode, modifiers, label in
            self.actionKeyCode = keyCode
            self.actionModifiers = modifiers
            self.actionKeyLabel = label
            self.isRecordingActionKey = false
            self.keyRecorder = nil
        }
    }
}

// MARK: - Key Recorder Helper

class KeyRecorderHelper {
    private var monitor: Any?
    private let onRecord: (UInt16, UInt64, String) -> Void

    init(onRecord: @escaping (UInt16, UInt64, String) -> Void) {
        self.onRecord = onRecord
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event: event)
            return nil // Consume
        }
    }

    private func capture(event: NSEvent) {
        guard let monitor = monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let label = KeyRecorderHelper.labelFor(keyCode: keyCode, modifiers: modifiers, characters: event.charactersIgnoringModifiers ?? "")
        let rawMods = CGEventFlags(modifierFlags: modifiers).rawValue
        onRecord(keyCode, rawMods, label)
    }

    static func labelFor(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName = keyNameForKeyCode(keyCode, characters: characters)
        parts.append(keyName)
        return parts.joined()
    }

    static func keyNameForKeyCode(_ keyCode: UInt16, characters: String) -> String {
        switch keyCode {
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x69: return "F13"
        case 0x6B: return "F14"
        case 0x71: return "F15"
        case 0x6A: return "F16"
        case 0x40: return "F17"
        case 0x4F: return "F18"
        case 0x50: return "F19"
        case 0x5A: return "F20"
        case 0x33: return "⌫"
        case 0x35: return "⎋"
        case 0x24: return "↩"
        case 0x30: return "⇥"
        case 0x31: return "Space"
        case 0x75: return "⌦"
        case 0x73: return "↖"
        case 0x77: return "↘"
        case 0x74: return "⇞"
        case 0x79: return "⇟"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        default:
            if !characters.isEmpty && characters != "\u{0}" {
                return characters.uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }
}

// MARK: - CGEventFlags from NSEvent.ModifierFlags

extension CGEventFlags {
    init(modifierFlags: NSEvent.ModifierFlags) {
        var flags: CGEventFlags = []
        if modifierFlags.contains(.shift) { flags.insert(.maskShift) }
        if modifierFlags.contains(.control) { flags.insert(.maskControl) }
        if modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
        if modifierFlags.contains(.command) { flags.insert(.maskCommand) }
        self = flags
    }
}

// MARK: - App Blocklist Tab

struct AppBlocklistTab: View {
    @EnvironmentObject var engine: ScrollEngine
    @ObservedObject var settings = ScrollSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(settings.blockedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundColor(.secondary)
                        }
                        Text(engine.appName(for: bundleID))
                        Spacer()
                        Button {
                            engine.removeFromBlocklist(bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }.buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack {
                Text("StylusScroll pauses automatically in these apps.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Add \(engine.activeAppName.isEmpty ? "Current App" : engine.activeAppName)") {
                    engine.addCurrentAppToBlocklist()
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

// MARK: - System Tab

struct SystemTab: View {
    @EnvironmentObject var engine: ScrollEngine

    var body: some View {
        Form {
            Section("System") {
                LaunchAtLoginToggle()
                HStack {
                    VStack(alignment: .leading) {
                        Text("Accessibility permission")
                        Text(engine.hasAccessibilityPermission ? "Granted ✓" : "Not granted")
                            .font(.caption)
                            .foregroundColor(engine.hasAccessibilityPermission ? .green : .orange)
                    }
                    Spacer()
                    if !engine.hasAccessibilityPermission {
                        Button("Open System Settings") { engine.requestAccessibilityPermission() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                HStack {
                    Text("Event tap")
                    Spacer()
                    Text(engine.isRunning ? "Running" : "Stopped")
                        .foregroundColor(engine.isRunning ? .green : .red)
                }
            }
            Section("About") {
                HStack {
                    Text("StylusScroll")
                    Spacer()
                    Text("Version 0.32.1").foregroundColor(.secondary)
                }
                Link("Find me on GitHub!", destination: URL(string: "https://github.com/meeer-theblackintels")!)
                Link("Buy me a coffee?", destination: URL(string: "https://github.com/meeer-theblackintels")!)
            }
        }
        .formStyle(.grouped)
    }
}
