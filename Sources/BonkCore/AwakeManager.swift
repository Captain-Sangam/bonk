import Foundation

public final class AwakeManager: AwakeManaging {
    private var activity: NSObjectProtocol?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
            reason: "Bonk Guard Mode is active"
        )
    }

    public func stop() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
