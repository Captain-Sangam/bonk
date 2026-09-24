import AppKit
import BonkCore
import SwiftUI

@main
struct BonkMenuBarApp: App {
    @NSApplicationDelegateAdaptor(BonkAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        BonkAppDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class BonkAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        guard let model = Self.model else { return }
        model.start()
        if !model.settings.onboardingComplete {
            OnboardingWindowController.shared.show(model: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.model?.shutdown()
    }
}

@MainActor
private final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let rootView = OnboardingView(model: model) { [weak self] in
            self?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meet Bonk"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
        window = nil
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var guardController: GuardController

    init(model: AppModel) {
        self.model = model
        guardController = model.guardController
    }

    var body: some View {
        Image(systemName: guardController.isGuarding ? "pawprint.fill" : "pawprint")
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var guardController: GuardController
    @ObservedObject private var settings: SettingsStore

    init(model: AppModel) {
        self.model = model
        guardController = model.guardController
        settings = model.settings
    }

    var body: some View {
        Button(guardController.isGuarding ? "Authenticate to Unbonk" : "Bonk this Mac") {
            model.toggleGuard()
        }
        .keyboardShortcut(shortcutEquivalent, modifiers: [.command, .shift])

        Divider()

        Toggle("Keep Awake", isOn: $settings.keepAwake)

        HStack {
            Text("Character")
            Spacer()
            Text("Fox")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Settings…") {
            NSApplication.shared.sendAction(
                Selector(("showSettingsWindow:")),
                to: nil,
                from: nil
            )
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Button("About Bonk") {
            NSApplication.shared.orderFrontStandardAboutPanel(
                options: [
                    .applicationName: "Bonk",
                    .applicationVersion: "0.1.0",
                    .credits: NSAttributedString(string: "Hands off. Bonk on.")
                ]
            )
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            model.shutdown()
            NSApplication.shared.terminate(nil)
        }

        if let error = guardController.lastError {
            Divider()
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var shortcutEquivalent: KeyEquivalent {
        KeyEquivalent(settings.shortcutKey.lowercased().first ?? "b")
    }
}
