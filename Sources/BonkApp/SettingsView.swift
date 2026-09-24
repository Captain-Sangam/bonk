import BonkCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var apiKey = ""
    @State private var savedKeySuffix: String?
    @State private var keyConfirmation: String?

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        self.settings = settings
        _savedKeySuffix = State(initialValue: settings.jevAPIKey.map { String($0.suffix(4)) })
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

            Section("Reactions") {
                Toggle("AI-powered reactions with Jev", isOn: $settings.aiReactionsEnabled)
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

            Section("Shortcut") {
                HStack {
                    Text("Toggle Bonk")
                    Spacer()
                    Text("⇧⌘")
                    TextField("B", text: $settings.shortcutKey)
                        .frame(width: 36)
                        .onChange(of: settings.shortcutKey) { value in
                            settings.shortcutKey = String(value.uppercased().prefix(1))
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
        .frame(width: 480, height: 500)
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
