import AppKit
import BonkCore
import SwiftUI

@main
@MainActor
private struct BonkCharacterGallery {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let galleryURL = URL(
            fileURLWithPath: arguments.first ?? "/private/tmp/bonk-character-gallery.png"
        )
        try render(
            CharacterGalleryView(),
            size: CGSize(width: 900, height: 850),
            to: galleryURL
        )

        if arguments.count > 1 {
            let previewURL = URL(fileURLWithPath: arguments[1])
            try render(
                GuardModePreviewView(),
                size: CGSize(width: 1200, height: 760),
                to: previewURL
            )
        }
    }

    private static func render<Content: View>(
        _ content: Content,
        size: CGSize,
        to outputURL: URL
    ) throws {
        let view = content
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.055, green: 0.06, blue: 0.09))

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw GalleryError.renderFailed
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryError.renderFailed
        }
        try png.write(to: outputURL, options: .atomic)
        print("Rendered \(outputURL.path)")
    }
}

private struct GuardModePreviewView: View {
    private let presentation = CharacterPresentation(
        state: .bonk,
        message: "BONK!",
        position: .resting,
        intensity: 0.9,
        lookX: 0.65,
        lookY: 0.2,
        facing: 1,
        motionSpeed: 0.8,
        variant: 3,
        reactionStartedAt: Date.timeIntervalSinceReferenceDate - 0.2,
        tone: .dramatic,
        pacing: .escalate,
        flourish: .pose,
        typingScalePeak: 1.65,
        typingDecayStartsAt: Date.timeIntervalSinceReferenceDate + 1
    )

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.19),
                    Color(red: 0.18, green: 0.12, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle().fill(Color.white.opacity(0.82)).frame(width: 10, height: 10)
                    Text("Bonk is guarding this Mac")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("Press Esc twice to unlock")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(Color.black.opacity(0.28))

                Spacer()
            }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .frame(width: 650, height: 350)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 14) {
                        Capsule().fill(Color.white.opacity(0.16)).frame(width: 210, height: 18)
                        Capsule().fill(Color.white.opacity(0.1)).frame(width: 510, height: 12)
                        Capsule().fill(Color.white.opacity(0.1)).frame(width: 440, height: 12)
                        HStack(spacing: 14) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.07))
                                    .frame(width: 155, height: 170)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding(30)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .offset(x: -95, y: 15)

            Circle()
                .stroke(Color.white.opacity(0.52), lineWidth: 3)
                .frame(width: 34, height: 34)
                .overlay(Circle().fill(Color.white).frame(width: 7, height: 7))
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                .offset(x: 305, y: 92)

            VStack(spacing: 2) {
                Text("BONK!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Color(red: 0.12, green: 0.08, blue: 0.2).opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .zIndex(2)

                BonkCharacterView(presentation: presentation)
                    .frame(width: 230, height: 235)
                    .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                    .zIndex(1)
            }
            .offset(x: 390, y: 170)

            VStack(alignment: .leading, spacing: 5) {
                Text("INPUT BLOCKED. JEV DIRECTING.")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                Text("Your desktop stays visible. Bonk handles the rest.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                HStack(spacing: 9) {
                    badge("120 HZ LOCAL CURSOR")
                    badge("TYPING ENERGY 1.65×")
                    badge("DRAMATIC · ESCALATE · POSE")
                }
                .padding(.top, 10)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(38)
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.09))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: Capsule())
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
        ("Unlock", .point, "Double-tap Esc.", 0.8, 0.8),
        ("Celebrate", .celebrate, "BONK OFF!", 0, 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BONK CHARACTER SYSTEM")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Original fox mascot • instant local cursor • Jev-directed state, tone, pacing, flourish and dialogue")
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
        .background(Color(red: 0.055, green: 0.06, blue: 0.09))
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
