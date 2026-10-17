import AppKit
import Combine
import SwiftUI

/// Scans the running-process table for agents whose `comm` basename matches a configured
/// pattern list, and publishes their names for the away-screen. No protocol / DI: the overlay
/// is the only consumer and owns its lifecycle (start in `show()`, stop in `hide()`).
@MainActor
public final class AgentMonitor: ObservableObject {
    @Published public private(set) var agents: [String] = []

    private let patterns: [String]
    private var task: Task<Void, Never>?

    public init(patterns: [String]) {
        self.patterns = patterns
    }

    public func start() {
        task?.cancel()
        let pats = patterns
        // Sequential loop on the main actor; the actual `ps` call runs detached (off-main) so
        // it can never block the main run loop that hosts the input tap.
        task = Task { [weak self] in
            while !Task.isCancelled {
                let names = await Task.detached { AgentMonitor.runScan(patterns: pats) }.value
                if Task.isCancelled { return }
                self?.agents = names
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    nonisolated private static func runScan(patterns: [String]) -> [String] {
        guard !patterns.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        // Drain the pipe to EOF BEFORE waiting: a large process list can fill the pipe buffer
        // and deadlock `waitUntilExit()` if we wait first.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return matches(in: output, patterns: patterns)
    }

    /// Exact `comm` basename match (lowercased), deduped and sorted. Exact, not substring, so a
    /// pattern never accidentally matches an unrelated binary.
    public nonisolated static func matches(in psOutput: String, patterns: [String]) -> [String] {
        let wanted = Set(patterns.map { $0.lowercased() }).subtracting([""])
        guard !wanted.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for rawLine in psOutput.split(separator: "\n") {
            let full = rawLine.trimmingCharacters(in: .whitespaces)
            guard !full.isEmpty else { continue }
            let base = (full as NSString).lastPathComponent.lowercased()
            guard wanted.contains(base) else { continue }
            if seen.insert(base).inserted { result.append(base) }
        }
        return result.sorted()
    }
}

/// The locked "Waveform" away-screen: lock + AWAY wordmark + running pill + animated
/// multi-harmonic waveform + clock + "Locked · back soon", on black. Rendered on every display.
struct AwayScreenView: View {
    @ObservedObject var monitor: AgentMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var now = Date()
    private let clock = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private let accent = Color(red: 0.486, green: 0.549, blue: 1.0)   // #7c8cff
    private let ok = Color(red: 0.357, green: 0.718, blue: 0.604)     // #5bb79a

    var body: some View {
        GeometryReader { geo in
            let scale = max(0.65, min(1.7, geo.size.height / 900))
            ZStack {
                Color.black
                VStack(spacing: 20 * scale) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 38 * scale, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))

                    Text("AWAY")
                        .font(.system(size: 15 * scale, weight: .regular))
                        .tracking(14 * scale)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.leading, 14 * scale)

                    pill(scale: scale)

                    if !monitor.agents.isEmpty {
                        Text(monitor.agents.joined(separator: "  ·  "))
                            .font(.system(size: 15 * scale, weight: .light, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: geo.size.width * 0.7)
                    }

                    waveform
                        .frame(width: min(geo.size.width * 0.55, 560), height: 90 * scale)

                    Text(clockString)
                        .font(.system(size: 76 * scale, weight: .ultraLight))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Locked · back soon")
                        .font(.system(size: 13 * scale, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
        }
        .onReceive(clock) { now = $0 }
    }

    @ViewBuilder
    private func pill(scale: CGFloat) -> some View {
        let count = monitor.agents.count
        let label = count == 0 ? "No agents running"
            : "\(count) agent\(count == 1 ? "" : "s") running"
        HStack(spacing: 10 * scale) {
            if count > 0 {
                PresenceDot(color: ok, reduceMotion: reduceMotion)
                    .frame(width: 9 * scale, height: 9 * scale)
            }
            Text(label.uppercased())
                .font(.system(size: 13 * scale, weight: .regular, design: .monospaced))
                .tracking(2 * scale)
                .foregroundStyle(count == 0 ? .white.opacity(0.4) : ok)
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 8 * scale)
        .overlay(
            Capsule().stroke((count == 0 ? Color.white.opacity(0.18) : ok.opacity(0.4)), lineWidth: 1)
        )
    }

    private var clockString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let path = Self.wavePath(size: size, t: t)
                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.stroke(path, with: .color(accent.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(0), accent, accent.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: size.height / 2),
                        endPoint: CGPoint(x: size.width, y: size.height / 2)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// Three harmonics with an edge-tapering envelope and a slow amplitude breath.
    private static func wavePath(size: CGSize, t: TimeInterval) -> Path {
        var path = Path()
        let width = size.width
        let mid = size.height / 2
        guard width > 1 else { return path }
        let steps = max(2, Int(width))
        let amp = size.height * 0.33 * (0.78 + 0.22 * sin(t * 0.9))
        let norm = 1.0 + 0.46 + 0.26
        for i in 0...steps {
            let xN = Double(i) / Double(steps)
            let phase = xN * 2 * Double.pi * 2.3
            let env = sin(Double.pi * xN)
            let v = (sin(phase + t * 1.1)
                     + 0.46 * sin(phase * 2.3 - t * 1.7)
                     + 0.26 * sin(phase * 3.7 + t * 2.1)) / norm
            let x = CGFloat(xN) * width
            let y = mid - CGFloat(env * v) * amp
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

/// A soft presence dot: the core plus two slowly expanding, fading rings (no cheap blink).
private struct PresenceDot: View {
    let color: Color
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ring(delay: 0)
                ring(delay: 1.5)
            }
            Circle().fill(color)
        }
        .onAppear { animate = true }
    }

    private func ring(delay: Double) -> some View {
        Circle()
            .stroke(color, lineWidth: 1)
            .scaleEffect(animate ? 3.6 : 1)
            .opacity(animate ? 0 : 0.55)
            .animation(
                .easeOut(duration: 3).repeatForever(autoreverses: false).delay(delay),
                value: animate
            )
    }
}
