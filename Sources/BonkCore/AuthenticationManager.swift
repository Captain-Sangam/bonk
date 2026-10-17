import Foundation
import LocalAuthentication

public final class AuthenticationManager: OwnerAuthenticating {
    public init() {}

    public func authenticateOwner() async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Mac Password"
        context.localizedCancelTitle = "Keep Bonk On"

        var authorizationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authorizationError) else {
            throw BonkError.authenticationUnavailable(
                authorizationError?.localizedDescription ?? "No device-owner authentication method is available."
            )
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Bonk"
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Self.mapFailure(error))
                }
            }
        }
    }

    /// Classify an evaluation failure. Only a genuine rejection becomes `authenticationFailed`
    /// (the single case that triggers the intrusion camera). Cancellations and every other
    /// condition are kept distinct so a dismissed sheet never counts as an intruder.
    static func mapFailure(_ error: Error?) -> BonkError {
        let reason = error?.localizedDescription ?? "Authentication was cancelled."
        guard let code = (error as? LAError)?.code else {
            // No recognizable code: treat as unavailable, never as a failed attempt.
            return .authenticationUnavailable(reason)
        }
        switch code {
        case .authenticationFailed:
            return .authenticationFailed(reason)
        case .userCancel, .appCancel, .systemCancel:
            return .authenticationCancelled(reason)
        default:
            // userFallback, biometryLockout, passcodeNotSet, invalidContext, notInteractive, …
            return .authenticationUnavailable(reason)
        }
    }
}
