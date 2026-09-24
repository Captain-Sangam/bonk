import SwiftUI

public struct BonkCharacterView: View {
    public let presentation: CharacterPresentation

    public init(presentation: CharacterPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            BonkCatDrawing(
                presentation: presentation,
                elapsed: max(0, timeline.date.timeIntervalSinceReferenceDate - presentation.reactionStartedAt)
            )
        }
        .frame(width: 132, height: 146, alignment: .bottom)
        .accessibilityLabel("Bonk cat: \(presentation.state.rawValue)")
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

    private let ink = Color(red: 0.13, green: 0.10, blue: 0.22)
    private let fur = Color(red: 0.98, green: 0.55, blue: 0.22)
    private let lightFur = Color(red: 1.00, green: 0.82, blue: 0.54)
    private let accent = Color(red: 0.98, green: 0.24, blue: 0.30)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.2))
                .frame(width: 78, height: 13)
                .offset(y: 46)
                .scaleEffect(x: shadowScale, y: 1)

            tail
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
            Capsule()
                .fill(ink)
                .frame(width: 58, height: 18)
            Capsule()
                .fill(fur)
                .frame(width: 52, height: 12)
        }
        .rotationEffect(.degrees(-30 + tailSwing))
        .offset(x: -40, y: 21)
    }

    private var torso: some View {
        ZStack {
            Capsule()
                .fill(ink)
                .frame(width: 76, height: 54)
            Capsule()
                .fill(fur)
                .frame(width: 68, height: 46)
            Ellipse()
                .fill(lightFur.opacity(0.9))
                .frame(width: 35, height: 28)
                .offset(x: 10, y: 5)
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
            ear(x: -27, rotation: -13)
            ear(x: 27, rotation: 13)
        }
        .offset(y: -31)
    }

    private func ear(x: CGFloat, rotation: Double) -> some View {
        ZStack {
            BonkEarShape().fill(ink).frame(width: 32, height: 39)
            BonkEarShape().fill(accent.opacity(0.78)).frame(width: 20, height: 27).offset(y: 5)
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
            Ellipse().fill(lightFur).frame(width: 42, height: 27).offset(y: 10)
            BonkNoseShape().fill(accent).frame(width: 11, height: 8).offset(y: 4)
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
        .offset(y: 11)
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
        case .bonk:
            BonkMalletView(angle: malletAngle, ink: ink, accent: accent)
                .offset(x: 48, y: -35)
        case .swat:
            ZStack {
                Circle().fill(ink).frame(width: 26, height: 26)
                Circle().fill(lightFur).frame(width: 20, height: 20)
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
        case .bonk, .pounce, .celebrate: return .open
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
