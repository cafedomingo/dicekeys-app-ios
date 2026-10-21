//
//  DeviceOwner.swift
//  DiceKeys
//

import LocalAuthentication

enum DeviceOwner {
    /// Face ID, Touch ID or the passcode; throws if none is set up or the check fails.
    static func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? LAError(.passcodeNotSet)
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw LAError(.authenticationFailed)
        }
        return context
    }
}

extension Error {
    /// The user, or the system, canceled an authentication prompt: not worth reporting.
    var isAuthenticationCancellation: Bool {
        guard let laError = self as? LAError else { return false }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: return true
        default: return false
        }
    }
}
