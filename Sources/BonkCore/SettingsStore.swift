import Combine
import Foundation
import ServiceManagement

@MainActor
public final class SettingsStore: ObservableObject {
    public static let jevAPIKeyAccount = "typesafe-api-key"

    @Published public var keepAwake: Bool {
        didSet { defaults.set(keepAwake, forKey: Keys.keepAwake) }
    }

    @Published public var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.soundsEnabled) }
    }

    @Published public var aiReactionsEnabled: Bool {
        didSet { defaults.set(aiReactionsEnabled, forKey: Keys.aiReactionsEnabled) }
    }

    @Published public var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Keys.onboardingComplete) }
    }

    @Published public var shortcutKey: String {
        didSet { defaults.set(shortcutKey, forKey: Keys.shortcutKey) }
    }

    @Published public private(set) var launchAtLogin: Bool
    @Published public private(set) var lastError: String?

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        keepAwake = defaults.object(forKey: Keys.keepAwake) as? Bool ?? true
        soundsEnabled = defaults.object(forKey: Keys.soundsEnabled) as? Bool ?? true
        aiReactionsEnabled = defaults.object(forKey: Keys.aiReactionsEnabled) as? Bool ?? false
        onboardingComplete = defaults.object(forKey: Keys.onboardingComplete) as? Bool ?? false
        shortcutKey = defaults.string(forKey: Keys.shortcutKey) ?? "B"
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    public var jevAPIKey: String? {
        let keychainValue = keychain.string(for: Self.jevAPIKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let keychainValue, !keychainValue.isEmpty {
            return keychainValue
        }

        let environmentValue = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return environmentValue?.isEmpty == false ? environmentValue : nil
    }

    public func saveJevAPIKey(_ value: String) {
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try keychain.remove(Self.jevAPIKeyAccount)
            } else {
                try keychain.set(trimmed, for: Self.jevAPIKeyAccount)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            lastError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            lastError = BonkError.launchAtLoginUnavailable(error.localizedDescription).localizedDescription
        }
    }

    public func clearError() {
        lastError = nil
    }

    private enum Keys {
        static let keepAwake = "keepAwake"
        static let soundsEnabled = "soundsEnabled"
        static let aiReactionsEnabled = "aiReactionsEnabled"
        static let onboardingComplete = "onboardingComplete"
        static let shortcutKey = "shortcutKey"
    }
}
