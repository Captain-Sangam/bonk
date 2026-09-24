import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class InputInterceptor: InputIntercepting {
    public var onSignal: ((InteractionSignal) -> Void)?
    public var onAuthenticationGesture: (() -> Void)?
    public var onFailure: ((BonkError) -> Void)?

    public private(set) var isRunning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?
    private var lastClickDate = Date.distantPast
    private var lastMovementSignalDate: Date?
    private var virtualMouseLocation: CGPoint?
    private var pendingMovementDeltaX: Double = 0
    private var pendingMovementDeltaY: Double = 0
    private var escapeSequenceDetector = EscapeSequenceDetector()

    public init() {}

    deinit {
        stop()
    }

    public static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    public func start(promptForPermission: Bool = true) throws {
        guard !isRunning else { return }
        guard Self.hasAccessibilityPermission(prompt: promptForPermission) else {
            throw BonkError.accessibilityPermissionMissing
        }

        let mask = Self.eventTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: bonkEventTapCallback,
            userInfo: userInfo
        ) else {
            throw BonkError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        virtualMouseLocation = NSEvent.mouseLocation
        isRunning = true
        startWatchdog()
    }

    public func stop() {
        watchdog?.invalidate()
        watchdog = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        isRunning = false
        lastMovementSignalDate = nil
        virtualMouseLocation = nil
        pendingMovementDeltaX = 0
        pendingMovementDeltaY = 0
        escapeSequenceDetector.reset()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            isRunning = false
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?(.eventTapDisabled)
            }
            return Unmanaged.passUnretained(event)
        }

        let now = Date()
        let eventLocation = Self.appKitLocation(for: event.location)
        var location = virtualMouseLocation ?? eventLocation

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let eventDeltaX = Double(event.getIntegerValueField(.mouseEventDeltaX))
            let eventDeltaY = -Double(event.getIntegerValueField(.mouseEventDeltaY))
            location = Self.clampToDisplays(
                CGPoint(
                    x: location.x + eventDeltaX,
                    y: location.y + eventDeltaY
                )
            )
            virtualMouseLocation = location
            pendingMovementDeltaX += eventDeltaX
            pendingMovementDeltaY += eventDeltaY

            let elapsed = lastMovementSignalDate.map { now.timeIntervalSince($0) } ?? .infinity
            if elapsed >= 1.0 / 60.0 {
                let deltaX = pendingMovementDeltaX
                let deltaY = pendingMovementDeltaY
                let distance = hypot(deltaX, deltaY)
                let speed = elapsed.isFinite && elapsed > 0 ? distance / elapsed : 0
                lastMovementSignalDate = now
                pendingMovementDeltaX = 0
                pendingMovementDeltaY = 0
                onSignal?(
                    InteractionSignal(
                        kind: .mouseMovement,
                        timestamp: now,
                        globalLocation: location,
                        magnitude: speed,
                        deltaX: deltaX,
                        deltaY: deltaY
                    )
                )
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            virtualMouseLocation = location
            let isRapid = now.timeIntervalSince(lastClickDate) < 0.35
            lastClickDate = now
            onSignal?(
                InteractionSignal(
                    kind: isRapid ? .rapidClick : .click,
                    timestamp: now,
                    globalLocation: location
                )
            )

        case .scrollWheel:
            let vertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let horizontal = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            onSignal?(
                InteractionSignal(
                    kind: .scroll,
                    timestamp: now,
                    globalLocation: location,
                    magnitude: max(abs(vertical), abs(horizontal)),
                    deltaX: horizontal,
                    deltaY: vertical
                )
            )

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if escapeSequenceDetector.register(
                keyCode: keyCode,
                isRepeat: isRepeat,
                at: now.timeIntervalSinceReferenceDate
            ) {
                onAuthenticationGesture?()
                break
            }

            let flags = event.flags
            let isShortcut = flags.contains(.maskCommand)
                || flags.contains(.maskControl)
                || flags.contains(.maskAlternate)
            onSignal?(
                InteractionSignal(
                    kind: isShortcut ? .shortcutAttempt : .keyboardActivity,
                    timestamp: now,
                    globalLocation: location
                )
            )

        default:
            break
        }

        // Returning nil suppresses the event before it reaches applications.
        return nil
    }

    private static func appKitLocation(for quartzLocation: CGPoint) -> CGPoint {
        // CGEvent uses a top-left global origin while AppKit screen frames use
        // the bottom-left of the primary display. The same transform continues
        // to work for displays arranged above or below the primary display.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: quartzLocation.x, y: primaryTop - quartzLocation.y)
    }

    private static func clampToDisplays(_ point: CGPoint) -> CGPoint {
        let displayBounds = NSScreen.screens.reduce(CGRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        guard !displayBounds.isNull, !displayBounds.isEmpty else { return point }
        return CGPoint(
            x: min(max(point.x, displayBounds.minX), displayBounds.maxX - 1),
            y: min(max(point.y, displayBounds.minY), displayBounds.maxY - 1)
        )
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, let tap = self.eventTap else { return }
            guard CGEvent.tapIsEnabled(tap: tap) else {
                self.isRunning = false
                self.onFailure?(.eventTapDisabled)
                return
            }
        }
    }

    private static let eventTypes: [CGEventType] = [
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
        .keyDown,
        .keyUp,
        .flagsChanged
    ]
}

struct EscapeSequenceDetector {
    static let escapeKeyCode: Int64 = 53
    static let maximumInterval: TimeInterval = 0.65

    private var firstEscapeAt: TimeInterval?

    mutating func register(keyCode: Int64, isRepeat: Bool, at timestamp: TimeInterval) -> Bool {
        guard !isRepeat else { return false }
        guard keyCode == Self.escapeKeyCode else {
            reset()
            return false
        }

        if let firstEscapeAt,
           timestamp >= firstEscapeAt,
           timestamp - firstEscapeAt <= Self.maximumInterval {
            reset()
            return true
        }

        firstEscapeAt = timestamp
        return false
    }

    mutating func reset() {
        firstEscapeAt = nil
    }
}

private func bonkEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handle(type: type, event: event)
}
