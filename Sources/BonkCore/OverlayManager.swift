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

    private var shouldRenderCharacter: Bool {
        guard let active = characterEngine.presentation.activeDisplayNumber else {
            return isPrimaryDisplay
        }
        return active == displayNumber
    }

    private var shouldRenderCursor: Bool {
        guard let active = characterEngine.cursorPresentation.activeDisplayNumber else {
            return isPrimaryDisplay
        }
        return active == displayNumber
    }

    var body: some View {
        GeometryReader { geometry in
            if shouldRenderCharacter || shouldRenderCursor {
                ZStack {
                    if shouldRenderCursor, let cursor = characterEngine.cursorPresentation.position {
                        BonkCursorTargetView(presentation: characterEngine.presentation)
                            .position(
                                x: cursor.x * geometry.size.width,
                                y: (1 - cursor.y) * geometry.size.height
                            )
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }

                    if shouldRenderCharacter {
                        VStack(spacing: 1) {
                            if let message = characterEngine.presentation.message {
                                Text(message)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(
                                        bubbleColor.opacity(0.94),
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                                    .transition(.scale.combined(with: .opacity))
                                    .zIndex(2)
                            }

                            BonkCharacterView(presentation: characterEngine.presentation)
                                .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
                                .zIndex(1)
                        }
                        .position(
                            x: characterEngine.presentation.position.x * geometry.size.width,
                            y: (1 - characterEngine.presentation.position.y) * geometry.size.height
                        )
                        .animation(
                            .interactiveSpring(response: 0.24, dampingFraction: 0.72),
                            value: characterEngine.presentation
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .background(Color.clear)
    }

    private var bubbleColor: Color {
        switch characterEngine.presentation.tone {
        case .playful: return Color(red: 0.13, green: 0.10, blue: 0.22)
        case .smug: return Color(red: 0.09, green: 0.27, blue: 0.31)
        case .grumpy: return Color(red: 0.35, green: 0.12, blue: 0.10)
        case .encouraging: return Color(red: 0.11, green: 0.31, blue: 0.21)
        case .dramatic: return Color(red: 0.31, green: 0.08, blue: 0.24)
        case .sleepy: return Color(red: 0.16, green: 0.17, blue: 0.31)
        }
    }

}
