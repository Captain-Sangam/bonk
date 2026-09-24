import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class InputInterceptor: InputIntercepting {
    public var onSignal: ((InteractionSignal) -> Void)?
    public var onFailure: ((BonkError) -> Void)?

    public private(set) var isRunning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?
    private var lastClickDate = Date.distantPast
    private var lastMovementSignalDate = Date.distantPast

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
        let location = NSEvent.mouseLocation

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if now.timeIntervalSince(lastMovementSignalDate) >= 0.08 {
                lastMovementSignalDate = now
                onSignal?(InteractionSignal(kind: .mouseMovement, timestamp: now, globalLocation: location))
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
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
            let vertical = abs(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            let horizontal = abs(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
            onSignal?(
                InteractionSignal(
                    kind: .scroll,
                    timestamp: now,
                    globalLocation: location,
                    magnitude: max(vertical, horizontal)
                )
            )

        case .keyDown:
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
