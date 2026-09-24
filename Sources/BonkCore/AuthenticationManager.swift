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
                    continuation.resume(
                        throwing: BonkError.authenticationFailed(
                            error?.localizedDescription ?? "Authentication was cancelled."
                        )
                    )
                }
            }
        }
    }
}
