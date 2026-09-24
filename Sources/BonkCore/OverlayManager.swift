import AppKit
import Combine
import SwiftUI

@MainActor
public final class OverlayManager: OverlayManaging {
    private let characterEngine: CharacterEngine
    private var windows: [BonkOverlayWindow] = []
    private var displayObserver: AnyCancellable?
    private var isActive = false
    private var isCapturingInput = false

    public var onFailure: ((String) -> Void)?

    public init(characterEngine: CharacterEngine) {
        self.characterEngine = characterEngine
    }

    public func show() throws {
        guard !isActive else { return }
        guard !NSScreen.screens.isEmpty else {
            throw BonkError.overlayUnavailable("No connected display was available.")
        }
        isActive = true
        displayObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.rebuildWindows() }
        rebuildWindows()
    }

    public func setCapturingInput(_ capture: Bool) {
        isCapturingInput = capture
        windows.forEach { $0.setCapturingInput(capture) }
    }

    public func hide() {
        isActive = false
        isCapturingInput = false
        displayObserver = nil
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func rebuildWindows() {
        guard isActive else { return }
        windows.forEach { $0.close() }
        windows.removeAll()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            onFailure?(BonkError.overlayUnavailable("The display configuration became empty.").localizedDescription)
            return
        }

        for (index, screen) in screens.enumerated() {
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
            let view = CharacterOverlayView(
                characterEngine: characterEngine,
                displayNumber: number,
                isPrimaryDisplay: index == 0
            )
            let window = BonkOverlayWindow(screen: screen, rootView: view)
            window.setCapturingInput(isCapturingInput)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

private final class BonkOverlayWindow: NSWindow {
    private var capturesInput = false
    private let guardLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)

    override var canBecomeKey: Bool { capturesInput }
    override var canBecomeMain: Bool { false }

    init<Content: View>(screen: NSScreen, rootView: Content) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = guardLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: rootView)
        ignoresMouseEvents = true
    }

    func setCapturingInput(_ capture: Bool) {
        capturesInput = capture
        ignoresMouseEvents = !capture
        if capture {
            // Keep ordinary apps covered, but allow macOS authentication UI to
            // appear above Bonk and receive password fallback input.
            level = .floating
            makeKeyAndOrderFront(nil)
        } else {
            level = guardLevel
        }
    }
}

private struct CharacterOverlayView: View {
    @ObservedObject var characterEngine: CharacterEngine
    let displayNumber: Int?
    let isPrimaryDisplay: Bool

    private var shouldRender: Bool {
        guard let active = characterEngine.presentation.activeDisplayNumber else {
            return isPrimaryDisplay
        }
        return active == displayNumber
    }

    var body: some View {
        GeometryReader { geometry in
            if shouldRender {
                VStack(spacing: 5) {
                    if let message = characterEngine.presentation.message {
                        Text(message)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(radius: 4, y: 2)
                    }

                    Text(characterEmoji)
                        .font(.system(size: 58))
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                        .rotationEffect(rotation)
                        .scaleEffect(scale)
                }
                .position(
                    x: characterEngine.presentation.position.x * geometry.size.width,
                    y: (1 - characterEngine.presentation.position.y) * geometry.size.height
                )
                .animation(.spring(response: 0.32, dampingFraction: 0.68), value: characterEngine.presentation)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .background(Color.clear)
    }

    private var characterEmoji: String {
        switch characterEngine.presentation.state {
        case .sleeping: return "😴"
        case .angry: return "😾"
        case .celebrate: return "😸"
        case .point: return "😼☝️"
        default: return "😼"
        }
    }

    private var rotation: Angle {
        characterEngine.presentation.state == .tumble ? .degrees(25) : .zero
    }

    private var scale: CGFloat {
        characterEngine.presentation.state == .bonk ? 1.22 : 1
    }
}
