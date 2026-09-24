import AppKit
import Foundation

@MainActor
public final class ShortcutMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var key = "B"
    private var handler: (() -> Void)?

    public init() {}

    public func start(key: String, handler: @escaping () -> Void) {
        stop()
        self.key = String(key.uppercased().prefix(1))
        self.handler = handler

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matches(event) {
                self.handler?()
                return nil
            }
            return event
        }
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        handler = nil
    }

    private func handle(_ event: NSEvent) {
        if matches(event) {
            handler?()
        }
    }

    private func matches(_ event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.command, .shift]
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(required) else {
            return false
        }
        return event.charactersIgnoringModifiers?.uppercased() == key
    }
}
