import BonkCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var page = 0
    private let onDone: () -> Void

    init(model: AppModel, onDone: @escaping () -> Void) {
        self.model = model
        settings = model.settings
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 24) {
            BonkLogoView(size: 92)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
                .accessibilityHidden(true)

            Group {
                switch page {
                case 0:
                    intro
                case 1:
                    permission
                case 2:
                    aiChoice
                default:
                    finish
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
        .padding(32)
        .frame(width: 460)
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Text("Meet Bonk")
                .font(.largeTitle.bold())
            Text("Your tiny Mac bodyguard.")
                .foregroundStyle(.secondary)
            Button("Continue") { page = 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    private var permission: some View {
        VStack(spacing: 14) {
            Text("Bonk needs access to your keyboard and mouse")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("That’s how it stops unwanted input. Bonk never records what you type.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Enable Access") {
                _ = InputInterceptor.hasAccessibilityPermission(prompt: true)
                page = 2
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var aiChoice: some View {
        VStack(spacing: 14) {
            Text("Make Bonk more expressive")
                .font(.title2.bold())
            Text("AI reactions send TypeSafe AI a small anonymous summary such as “rapid clicking” or “keyboard activity.” Bonk never sends what was typed or what is on the screen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Keep Reactions On Device") {
                    settings.aiReactionsEnabled = false
                    page = 3
                }
                Button("Use AI Reactions") {
                    settings.aiReactionsEnabled = true
                    page = 3
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var finish: some View {
        VStack(spacing: 14) {
            Text("Ready to Bonk")
                .font(.title2.bold())
            Text("Click the menu-bar paw and choose “Bonk this Mac.”")
                .foregroundStyle(.secondary)
            Button("Done") {
                settings.onboardingComplete = true
                onDone()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
