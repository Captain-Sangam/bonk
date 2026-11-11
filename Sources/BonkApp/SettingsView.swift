import AppKit
import BonkCore
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var director: JevDirectorMonitor
    @ObservedObject private var guardController: GuardController
    @State private var apiKey = ""
    @State private var savedKeySuffix: String?
    @State private var keyConfirmation: String?
    @State private var cameraAuthorized: Bool
    @StateObject private var recorder: ShortcutRecorder

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        self.settings = settings
        self.director = model.jevDirector
        self.guardController = model.guardController
        _savedKeySuffix = State(initialValue: settings.jevAPIKey.map { String($0.suffix(4)) })
        _cameraAuthorized = State(initialValue: model.camera.isAuthorized)
        _recorder = StateObject(wrappedValue: ShortcutRecorder(model: model))
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch Bonk at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
                Toggle("Keep Mac awake while Bonked", isOn: $settings.keepAwake)
                Toggle("Character sounds", isOn: $settings.soundsEnabled)
            }

            Section("Bonk mode") {
                Picker("While Bonked, show", selection: $settings.bonkMode) {
                    ForEach(BonkMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(guardController.isGuarding)

                if guardController.isGuarding {
                    Text("Stop Bonk to change the mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.bonkMode == .agents {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent process names")
                            .font(.subheadline.weight(.semibold))
                        TextField("claude, codex, aider", text: $settings.agentPatterns)
                            .textFieldStyle(.roundedBorder)
                        Text("Comma-separated. The away-screen lists running processes whose name matches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Intrusion camera") {
                Toggle("Photograph failed unlock attempts", isOn: cameraBinding)

                if settings.cameraMonitorEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: cameraAuthorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(cameraAuthorized ? Color.green : Color.orange)
                        Text(cameraAuthorized ? "Camera access granted" : "Camera access needed — enable Bonk in System Settings → Privacy & Security → Camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("On a genuine failed unlock, Bonk saves one photo to ~/Pictures/Bonk and notes it when you unlock. Photos stay on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Jev reaction engine") {
                Toggle("Enable Jev character direction", isOn: $settings.aiReactionsEnabled)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Jev API key")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Image(systemName: savedKeySuffix == nil ? "key.horizontal" : "checkmark.seal.fill")
                            .foregroundStyle(savedKeySuffix == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(savedKeySuffix == nil ? "No key saved" : "Key saved securely")
                                .font(.subheadline.weight(.semibold))
                            if let savedKeySuffix {
                                Text("Ending in ••••\(savedKeySuffix)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (savedKeySuffix == nil ? Color.secondary : Color.green).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                (savedKeySuffix == nil ? Color.secondary : Color.green).opacity(0.2),
                                lineWidth: 1
                            )
                    )

                    SecureField("Paste TypeSafe API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save Key") { saveAPIKey() }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if savedKeySuffix != nil {
                            Button("Remove", role: .destructive) { removeAPIKey() }
                        }

                        if let keyConfirmation {
                            Text(keyConfirmation)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }

                Text("Only aggregated interaction categories and counts are sent. Typed content and screen contents never leave the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.aiReactionsEnabled {
                Section("Jev Director") {
                    HStack(spacing: 10) {
                        Image(systemName: directorIcon)
                            .foregroundStyle(directorColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(director.phase.label)
                                .font(.subheadline.weight(.semibold))
                            if let decision = director.lastDecision {
                                Text(decision)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(director.requestCount) calls")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Jev waits for a two-second quiet period, then directs the fox's next reaction, tone, pacing, flourish, intensity, and dialogue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shortcut") {
                LabeledContent("Start Bonk") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button(recorder.isRecording ? "Type a shortcut…" : settings.shortcut.displayString) {
                            recorder.isRecording ? recorder.stop() : recorder.start()
                        }
                        .help("Click, then press a new shortcut with ⌘ or ⌃. Esc cancels.")

                        if let message = recorder.message ?? model.shortcutError {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            if let error = settings.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500, height: 640)
    }

    private var cameraBinding: Binding<Bool> {
        Binding(
            get: { settings.cameraMonitorEnabled },
            set: { enabled in
                settings.cameraMonitorEnabled = enabled
                if enabled {
                    Task { cameraAuthorized = await model.camera.requestAccess() }
                }
            }
        )
    }

    private var directorIcon: String {
        switch director.phase {
        case .localOnly: return "bolt.slash"
        case .waiting: return "hourglass"
        case .directing: return "brain.head.profile"
        case .applied: return "sparkles"
        case .unavailable: return "arrow.triangle.2.circlepath"
        }
    }

    private var directorColor: Color {
        switch director.phase {
        case .applied: return .green
        case .directing: return .orange
        case .unavailable: return .yellow
        default: return .secondary
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.saveJevAPIKey(trimmed)
        guard settings.lastError == nil else {
            keyConfirmation = nil
            return
        }
        savedKeySuffix = String(trimmed.suffix(4))
        keyConfirmation = "Saved"
        apiKey = ""
    }

    private func removeAPIKey() {
        settings.saveJevAPIKey("")
        guard settings.lastError == nil else { return }
        savedKeySuffix = nil
        keyConfirmation = "Removed"
        apiKey = ""
    }
}

/// Records a new start shortcut. While recording, every key is consumed and the hot key is
/// suspended; it resumes only on the recorded key's release or on cancel, so a held key never starts Bonk.
@MainActor
private final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?

    private let model: AppModel
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var pending: Shortcut?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard !isRecording else { return }
        model.suspendShortcut()
        isRecording = true
        message = nil
        pending = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: NSApp.keyWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop() {
        guard isRecording else { return }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        keyMonitor = nil
        resignObserver = nil
        pending = nil
        isRecording = false
        model.resumeShortcut()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyUp {
            guard let pending, event.keyCode == pending.keyCode else { return }
            model.setShortcut(pending)
            stop()
            return
        }

        guard !event.isARepeat, pending == nil else { return }
        guard event.keyCode != UInt16(kVK_Escape) else {
            stop()
            return
        }
        do {
            pending = try Shortcut.recorded(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                characters: event.characters(byApplyingModifiers: [])
            )
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
