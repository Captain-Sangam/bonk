import AppKit
import BonkCore
import SwiftUI

@main
@MainActor
private struct BonkCharacterGallery {
    static func main() throws {
        let outputURL = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? "/private/tmp/bonk-character-gallery.png"
        )
        let size = CGSize(width: 900, height: 850)
        let view = CharacterGalleryView()
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.055, green: 0.06, blue: 0.09))

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw GalleryError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryError.renderFailed
        }
        try png.write(to: outputURL, options: .atomic)
        print("Rendered \(outputURL.path)")
    }
}

private struct CharacterGalleryView: View {
    private let samples: [(String, CharacterState, String, Double, Double)] = [
        ("Sleep", .sleeping, "guarding... probably.", 0, 0),
        ("Wake", .notice, "...oh?", -0.7, 0.2),
        ("Track", .walk, "I see that cursor.", 0.8, 0.1),
        ("Stalk", .stalk, "stealth mode.", 0.7, -0.2),
        ("Pounce", .pounce, "GOTCHA.", 0.5, 0.4),
        ("Bonk", .bonk, "BONK!", 0.6, -0.2),
        ("Swat", .swat, "hands off.", 0.9, 0),
        ("Repeat", .bonk, "rapid bonk mode.", -0.6, 0.2),
        ("Annoyed", .annoyed, "keyboard privileges revoked.", -0.5, 0),
        ("Typing", .coverEars, "my ears!", 0, 0),
        ("Angry", .angry, "you chose chaos.", -0.5, 0.2),
        ("Shortcut", .block, "absolutely not.", 0.7, 0),
        ("Scroll", .cling, "claws deployed.", 0.2, -0.8),
        ("Tumble", .tumble, "wheee—NO.", -0.4, 0.6),
        ("Unlock", .point, "Use the finger.", 0.8, 0.8),
        ("Celebrate", .celebrate, "BONK OFF!", 0, 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BONK CHARACTER SYSTEM")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Original fox mascot • local tracking • state-specific motion and props")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    VStack(spacing: 0) {
                        Text(sample.0.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.68))
                        BonkCharacterView(
                            presentation: CharacterPresentation(
                                state: sample.1,
                                message: nil,
                                position: .resting,
                                intensity: Double(index % 5) / 4,
                                lookX: sample.3,
                                lookY: sample.4,
                                facing: index.isMultiple(of: 3) ? -1 : 1,
                                motionSpeed: 0.7,
                                inputDeltaX: 0.7,
                                inputDeltaY: -0.3,
                                variant: index,
                                reactionStartedAt: Date.timeIntervalSinceReferenceDate - previewElapsed(for: sample.1)
                            )
                        )
                        .scaleEffect(0.82)
                        .frame(height: 120)
                        Text(sample.2)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
                }
            }
        }
        .padding(24)
    }

    private func previewElapsed(for state: CharacterState) -> TimeInterval {
        switch state {
        case .bonk, .swat: return 0.2
        case .pounce, .tumble: return 0
        default: return 0.1
        }
    }
}

private enum GalleryError: Error {
    case renderFailed
}
