import BonkCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var apiKey = ""

    init(model: AppModel) {
        self.model = model
        settings = model.settings
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
                SecureField("TypeSafe API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save API Key") {
                        settings.saveJevAPIKey(apiKey)
                        apiKey = ""
                    }
                    Text(settings.jevAPIKey == nil ? "No key configured" : "Key configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .frame(width: 480, height: 440)
    }
}
