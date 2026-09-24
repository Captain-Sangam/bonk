import BonkCore
import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.1.0"

    var body: some View {
        VStack(spacing: 14) {
            BonkAppIconView(size: 132)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 7)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Bonk")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text("Hands off. Bonk on.")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 220)
                .padding(.vertical, 3)

            VStack(spacing: 7) {
                Text("Version \(version)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("Copyright © 2026")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                Link(
                    "Captain-sangam",
                    destination: URL(string: "https://github.com/Captain-Sangam")!
                )
                .font(.system(.body, design: .rounded).weight(.semibold))
            }
        }
        .padding(30)
        .frame(width: 360, height: 390)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.indigo.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
