import AppKit
import SwiftUI

public struct BonkCharacterView: View {
    public let presentation: CharacterPresentation

    public init(presentation: CharacterPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - presentation.reactionStartedAt)
            if let sprite = BonkFoxSpriteAtlas.shared.sprite(for: presentation.state) {
                BonkFoxSpriteDrawing(
                    sprite: sprite,
                    presentation: presentation,
                    elapsed: elapsed
                )
            } else {
                BonkCatDrawing(presentation: presentation, elapsed: elapsed)
            }
        }
        .frame(width: 132, height: 146, alignment: .bottom)
        .accessibilityLabel("Bonk fox: \(presentation.state.rawValue)")
    }
}

private struct BonkFoxSpriteDrawing: View {
    let sprite: NSImage
    let presentation: CharacterPresentation
    let elapsed: TimeInterval

    var body: some View {
        Image(nsImage: sprite)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 138, height: 138)
            .scaleEffect(x: presentation.facing < 0 ? -1 : 1, y: verticalStretch)
            .rotationEffect(.degrees(bodyRotation))
            .offset(x: bodyOffset.width, y: bodyOffset.height)
    }

    private var gait: Double { sin(elapsed * (8 + (presentation.motionSpeed * 9))) }

    private var verticalStretch: CGFloat {
        switch presentation.state {
        case .pounce: return 1.06
        case .cling: return 0.91
        case .bonk, .repeatBonk: return 1 + (CGFloat(sin(min(elapsed / 0.34, 1) * .pi)) * 0.05)
        default: return 1
        }
    }

    private var bodyRotation: Double {
        switch presentation.state {
        case .tumble:
            let progress = min(elapsed / 0.72, 1)
            return progress * 360 + (sin(elapsed * 4) * 4)
        case .angry:
            return sin(elapsed * 34) * 2.5
        case .celebrate:
            return sin(elapsed * 11) * 6
        default:
            return 0
        }
    }

    private var bodyOffset: CGSize {
        switch presentation.state {
        case .notice:
            return CGSize(width: 0, height: CGFloat(-sin(min(elapsed / 0.38, 1) * .pi) * 12))
        case .walk, .stalk:
            return CGSize(width: 0, height: CGFloat(gait * 2.5))
        case .pounce:
            return CGSize(width: 0, height: CGFloat(-sin(min(elapsed / 0.58, 1) * .pi) * 28))
        case .angry:
            return CGSize(width: CGFloat(sin(elapsed * 38) * 3), height: 0)
        case .celebrate:
            return CGSize(width: 0, height: CGFloat(-abs(sin(elapsed * 7)) * 14))
        default:
            return .zero
        }
    }
}

@MainActor
private final class BonkFoxSpriteAtlas {
    static let shared = BonkFoxSpriteAtlas()

    private let sourceImage: CGImage?
    private var cache: [Int: NSImage] = [:]

    private init() {
        let packagedURL = Bundle.main.resourceURL?
            .appendingPathComponent("Bonk_BonkCore.bundle", isDirectory: true)
            .appendingPathComponent("bonk-fox-spritesheet.png")
        let url: URL?
        if let packagedURL, FileManager.default.fileExists(atPath: packagedURL.path) {
            url = packagedURL
        } else {
            url = Bundle.module.url(forResource: "bonk-fox-spritesheet", withExtension: "png")
        }

        guard let url,
              let image = NSImage(contentsOf: url)
        else {
            sourceImage = nil
            return
        }
        sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    func sprite(for state: CharacterState) -> NSImage? {
        let index = spriteIndex(for: state)
        if let cached = cache[index] { return cached }
        guard let sourceImage else { return nil }

        let column = index % 4
        let row = index / 4
        let x0 = Int((Double(column) * Double(sourceImage.width) / 4).rounded())
        let x1 = Int((Double(column + 1) * Double(sourceImage.width) / 4).rounded())
        let top0 = Int((Double(row) * Double(sourceImage.height) / 4).rounded())
        let top1 = Int((Double(row + 1) * Double(sourceImage.height) / 4).rounded())
        let cropRect = CGRect(
            x: x0,
            y: top0,
            width: x1 - x0,
            height: top1 - top0
        ).insetBy(dx: 12, dy: 12)
        guard let cropped = sourceImage.cropping(to: cropRect) else { return nil }

        let image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        cache[index] = image
        return image
    }

    private func spriteIndex(for state: CharacterState) -> Int {
        switch state {
        case .sleeping, .idle: return 0
        case .notice: return 1
        case .walk, .run: return 2
        case .stalk: return 3
        case .pounce: return 4
        case .bonk: return 5
        case .swat: return 6
        case .repeatBonk: return 7
        case .annoyed: return 8
        case .coverEars: return 9
        case .angry: return 10
        case .block: return 11
        case .cling, .dragged: return 12
        case .tumble: return 13
        case .point: return 14
        case .celebrate, .disappear: return 15
        }
    }
}

struct BonkCursorTargetView: View {
    let presentation: CharacterPresentation

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - presentation.reactionStartedAt)
            let impact = presentation.state == .bonk || presentation.state == .swat
            let pulse = impact ? min(elapsed / 0.34, 1) : 0

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.78), lineWidth: 2)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color(red: 1, green: 0.37, blue: 0.26))
                    .frame(width: 5, height: 5)
                Circle()
                    .stroke(Color(red: 1, green: 0.48, blue: 0.28).opacity(1 - pulse), lineWidth: 3)
                    .frame(width: 18 + (pulse * 44), height: 18 + (pulse * 44))
            }
            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
        }
        .frame(width: 68, height: 68)
    }
}

private struct BonkCatDrawing: View {
    let presentation: CharacterPresentation
    let elapsed: TimeInterval

    private let ink = Color(red: 0.20, green: 0.11, blue: 0.10)
    private let fur = Color(red: 1.00, green: 0.47, blue: 0.08)
    private let lightFur = Color(red: 1.00, green: 0.88, blue: 0.68)
    private let accent = Color(red: 0.96, green: 0.25, blue: 0.22)
    private let indigo = Color(red: 0.10, green: 0.16, blue: 0.31)
    private let teal = Color(red: 0.06, green: 0.43, blue: 0.49)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.2))
                .frame(width: 78, height: 13)
                .offset(y: 46)
                .scaleEffect(x: shadowScale, y: 1)

            tail
            arms
            torso
            legs
            head
            stateAccessory
        }
        .frame(width: 124, height: 112)
        .scaleEffect(x: presentation.facing < 0 ? -1 : 1, y: verticalStretch)
        .rotationEffect(.degrees(bodyRotation))
        .offset(x: bodyOffset.width, y: bodyOffset.height)
    }

    private var tail: some View {
        ZStack {
            BonkFoxTailShape().fill(ink).frame(width: 76, height: 70)
            BonkFoxTailShape().fill(fur).frame(width: 68, height: 62).offset(x: 3, y: 2)
            BonkTailTipShape().fill(lightFur).frame(width: 29, height: 34).offset(x: -20, y: -13)
        }
        .rotationEffect(.degrees(-15 + (tailSwing * 0.55)))
        .offset(x: -43, y: 11)
    }

    private var arms: some View {
        ZStack {
            foxArm(x: -34, rotation: -22)
            foxArm(x: 34, rotation: 22).scaleEffect(x: -1, y: 1)
        }
        .offset(y: 18)
    }

    private func foxArm(x: CGFloat, rotation: Double) -> some View {
        ZStack {
            Capsule().fill(ink).frame(width: 42, height: 18)
            Capsule().fill(fur).frame(width: 35, height: 12)
            Capsule().fill(teal).frame(width: 12, height: 14).offset(x: 10)
        }
        .rotationEffect(.degrees(rotation))
        .offset(x: x)
    }

    private var torso: some View {
        ZStack {
            Capsule()
                .fill(ink)
                .frame(width: 76, height: 54)
            Capsule()
                .fill(fur)
                .frame(width: 68, height: 46)
            BonkVestShape()
                .fill(indigo)
                .frame(width: 58, height: 45)
                .offset(y: -1)
            BonkChestShape()
                .fill(lightFur)
                .frame(width: 28, height: 24)
                .offset(y: -12)
            Capsule().fill(accent).frame(width: 57, height: 8).offset(y: 13)
            Circle().fill(accent).frame(width: 12, height: 12).offset(x: 14, y: 14)
        }
        .offset(y: 20)
    }

    private var legs: some View {
        ZStack {
            paw(x: -24, y: 42 + leftPawLift)
            paw(x: 24, y: 42 + rightPawLift)
        }
    }

    private func paw(x: CGFloat, y: CGFloat) -> some View {
        ZStack {
            Capsule().fill(ink).frame(width: 31, height: 19)
            Capsule().fill(lightFur).frame(width: 25, height: 13)
        }
        .offset(x: x, y: y)
    }

    private var head: some View {
        ZStack {
            ears
            BonkTuftShape().fill(ink).frame(width: 42, height: 27).offset(y: -40)
            BonkTuftShape().fill(fur).frame(width: 34, height: 22).offset(y: -37)
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(ink)
                .frame(width: 82, height: 66)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(fur)
                .frame(width: 74, height: 58)

            muzzle
            eyes
            whiskers
        }
        .offset(y: -13)
    }

    private var ears: some View {
        ZStack {
            ear(x: -30, rotation: -11)
            ear(x: 30, rotation: 11)
        }
        .offset(y: -39)
    }

    private func ear(x: CGFloat, rotation: Double) -> some View {
        ZStack {
            BonkEarShape().fill(ink).frame(width: 38, height: 52)
            BonkEarShape().fill(fur).frame(width: 32, height: 46).offset(y: 4)
            BonkEarShape().fill(lightFur).frame(width: 20, height: 34).offset(y: 10)
            BonkEarTipShape().fill(ink).frame(width: 32, height: 20).offset(y: -13)
        }
        .rotationEffect(.degrees(rotation + earTwitch))
        .offset(x: x)
    }

    private var eyes: some View {
        HStack(spacing: 12) {
            eye
            eye
        }
        .offset(y: -8)
    }

    private var eye: some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: 18, height: eyeHeight)
            Circle()
                .fill(ink)
                .frame(width: 7, height: 7)
                .offset(
                    x: CGFloat(presentation.lookX * 3.5),
                    y: CGFloat(-presentation.lookY * 2.5)
                )
            Circle()
                .fill(Color.white)
                .frame(width: 2.5, height: 2.5)
                .offset(x: -1.2, y: -1.2)
        }
    }

    private var muzzle: some View {
        ZStack {
            BonkFoxCheeksShape().fill(lightFur).frame(width: 78, height: 34).offset(y: 9)
            Ellipse().fill(lightFur).frame(width: 39, height: 25).offset(y: 11)
            BonkNoseShape().fill(ink).frame(width: 11, height: 8).offset(y: 4)
            BonkMouthShape(mood: mouthMood)
                .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 25, height: 13)
                .offset(y: 13)
        }
    }

    private var whiskers: some View {
        HStack(spacing: 41) {
            whiskerSet.scaleEffect(x: -1, y: 1)
            whiskerSet
        }
        .offset(y: 12)
        .opacity(0.7)
    }

    private var whiskerSet: some View {
        VStack(spacing: 5) {
            Capsule().fill(ink).frame(width: 21, height: 1.8).rotationEffect(.degrees(-8))
            Capsule().fill(ink).frame(width: 23, height: 1.8).rotationEffect(.degrees(7))
        }
    }

    @ViewBuilder
    private var stateAccessory: some View {
        switch presentation.state {
        case .sleeping:
            VStack(alignment: .leading, spacing: -5) {
                Text("z").font(.system(size: 14, weight: .heavy, design: .rounded))
                Text("Z").font(.system(size: 21, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.white)
            .offset(x: 47, y: -45)
        case .bonk, .repeatBonk:
            BonkMalletView(angle: malletAngle, ink: ink, accent: accent)
                .offset(x: 48, y: -35)
        case .swat:
            ZStack {
                Circle().fill(ink).frame(width: 28, height: 28)
                Circle().fill(fur).frame(width: 22, height: 22)
                Circle().fill(ink.opacity(0.75)).frame(width: 8, height: 8).offset(y: 3)
            }
            .offset(x: 48 + swatReach, y: -1)
        case .coverEars:
            ZStack {
                paw(x: -39, y: -28)
                paw(x: 39, y: -28)
            }
        case .angry:
            BonkStressMark().stroke(accent, lineWidth: 4).frame(width: 24, height: 24).offset(x: 45, y: -46)
        case .block:
            ZStack {
                Circle().stroke(accent, lineWidth: 5).frame(width: 40, height: 40)
                Capsule().fill(accent).frame(width: 43, height: 5).rotationEffect(.degrees(-45))
            }
            .background(Circle().fill(Color.white).frame(width: 34, height: 34))
            .offset(x: 46, y: -33)
        case .point:
            BonkArrowShape().fill(Color.white).frame(width: 26, height: 37).offset(x: 42, y: -52)
        case .cling:
            HStack(spacing: 9) {
                clawMarks
                clawMarks
            }
            .offset(y: 51)
        case .celebrate:
            BonkBurstView(color: lightFur, phase: elapsed).frame(width: 116, height: 104)
        default:
            EmptyView()
        }
    }

    private var clawMarks: some View {
        HStack(spacing: 2) {
            Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 10).rotationEffect(.degrees(15))
            Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 10)
            Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 10).rotationEffect(.degrees(-15))
        }
    }

    private var mouthMood: BonkMouthShape.Mood {
        switch presentation.state {
        case .angry, .annoyed, .coverEars, .block: return .frown
        case .bonk, .repeatBonk, .pounce, .celebrate: return .open
        default: return .neutral
        }
    }

    private var eyeHeight: CGFloat {
        switch presentation.state {
        case .sleeping: return 3
        case .annoyed, .stalk: return 9
        case .angry, .block: return 12
        default: return 21
        }
    }

    private var gait: Double { sin(elapsed * (8 + (presentation.motionSpeed * 9))) }
    private var leftPawLift: CGFloat {
        guard presentation.state == .walk || presentation.state == .stalk else { return 0 }
        return CGFloat(max(0, gait) * -8)
    }
    private var rightPawLift: CGFloat {
        guard presentation.state == .walk || presentation.state == .stalk else { return 0 }
        return CGFloat(max(0, -gait) * -8)
    }
    private var tailSwing: Double {
        let speed = presentation.state == .angry ? 22.0 : 4 + (presentation.motionSpeed * 9)
        return sin(elapsed * speed) * (presentation.state == .stalk ? 8 : 17)
    }
    private var earTwitch: Double {
        presentation.state == .notice ? sin(elapsed * 25) * 7 : 0
    }
    private var malletAngle: Double {
        let progress = min(elapsed / 0.42, 1)
        return -74 + (sin(progress * .pi) * 105)
    }
    private var swatReach: CGFloat {
        CGFloat(sin(min(elapsed / 0.34, 1) * .pi) * 24)
    }
    private var shadowScale: CGFloat {
        presentation.state == .pounce ? CGFloat(1 - min(sin(min(elapsed / 0.58, 1) * .pi) * 0.38, 0.38)) : 1
    }
    private var verticalStretch: CGFloat {
        switch presentation.state {
        case .pounce: return 1.06
        case .cling: return 0.88
        default: return 1
        }
    }
    private var bodyRotation: Double {
        switch presentation.state {
        case .tumble:
            let progress = min(elapsed / 0.72, 1)
            return progress * 360 + (sin(elapsed * 4) * 4)
        case .angry:
            return sin(elapsed * 34) * 3
        case .celebrate:
            return sin(elapsed * 11) * 7
        default:
            return 0
        }
    }
    private var bodyOffset: CGSize {
        switch presentation.state {
        case .notice:
            return CGSize(width: 0, height: -sin(min(elapsed / 0.38, 1) * .pi) * 13)
        case .walk, .stalk:
            return CGSize(width: 0, height: gait * 2.5)
        case .pounce:
            return CGSize(width: 0, height: -sin(min(elapsed / 0.58, 1) * .pi) * 30)
        case .angry:
            return CGSize(width: sin(elapsed * 38) * 3, height: 0)
        case .celebrate:
            return CGSize(width: 0, height: -abs(sin(elapsed * 7)) * 15)
        default:
            return .zero
        }
    }
}

private struct BonkMalletView: View {
    let angle: Double
    let ink: Color
    let accent: Color

    var body: some View {
        ZStack(alignment: .top) {
            Capsule().fill(ink).frame(width: 9, height: 48).offset(y: 14)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ink).frame(width: 47, height: 27)
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(accent).frame(width: 39, height: 19).offset(y: 4)
        }
        .frame(width: 50, height: 66)
        .rotationEffect(.degrees(angle), anchor: .bottom)
    }
}

private struct BonkBurstView: View {
    let color: Color
    let phase: TimeInterval

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: 15)
                    .offset(y: -48 - CGFloat(sin(phase * 5 + Double(index))) * 5)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
    }
}

private struct BonkEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BonkEarTipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.74))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BonkTuftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.23, y: rect.height * 0.43))
        path.addLine(to: CGPoint(x: rect.width * 0.39, y: rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BonkFoxCheeksShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.width * 0.77, y: rect.height * 0.31))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.75))
        path.addLine(to: CGPoint(x: rect.width * 0.70, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.30, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.height * 0.82)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.75))
        path.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width * 0.23, y: rect.height * 0.31))
        path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

private struct BonkFoxTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.height * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.13, y: rect.height * 0.78),
            control1: CGPoint(x: rect.width * 0.70, y: rect.maxY),
            control2: CGPoint(x: rect.width * 0.24, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.20),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.64),
            control2: CGPoint(x: rect.width * 0.02, y: rect.height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.19),
            control1: CGPoint(x: rect.width * 0.32, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.56, y: rect.height * 0.05)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.72),
            control1: CGPoint(x: rect.width * 0.91, y: rect.height * 0.32),
            control2: CGPoint(x: rect.width * 0.96, y: rect.height * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

private struct BonkTailTipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.22))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.68, y: rect.minY),
            control: CGPoint(x: rect.width * 0.33, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.61))
        path.addLine(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.72),
            control: CGPoint(x: rect.width * 0.30, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct BonkVestShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.16, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.46))
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.14, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.16))
        path.closeSubpath()
        return path
    }
}

private struct BonkChestShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.height * 0.36)
        )
        return path
    }
}

private struct BonkNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BonkMouthShape: Shape {
    enum Mood { case neutral, frown, open }
    let mood: Mood

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch mood {
        case .neutral:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.midY),
                control: CGPoint(x: rect.midX * 0.6, y: rect.maxY)
            )
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.midX * 1.4, y: rect.maxY)
            )
        case .frown:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
        case .open:
            path.addEllipse(in: rect.insetBy(dx: 5, dy: 1))
        }
        return path
    }
}

private struct BonkStressMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.55))
        path.move(to: CGPoint(x: rect.maxX, y: rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.55))
        return path
    }
}

private struct BonkArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width * 0.67, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.42))
        path.closeSubpath()
        return path
    }
}
