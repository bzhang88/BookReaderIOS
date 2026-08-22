import SwiftUI
import LocalAuthentication

/// Full-screen gate shown before any app content when a local access password is configured --
/// calls `onUnlock` the moment verification succeeds. Attempts Face ID/Touch ID first when the
/// user has opted into it (`AppLockStore.isBiometricEnabled`), with the password field always
/// available as a fallback -- a failed or cancelled biometric prompt never locks the user out,
/// it just leaves them at the password field they'd have seen anyway.
struct AppLockView: View {
    let onUnlock: () -> Void

    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isAuthenticatingBiometric = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("输入密码解锁").font(.headline)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .onSubmit { attemptUnlock() }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            Button("解锁") { attemptUnlock() }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            if AppLockStore.isBiometricEnabled {
                Button {
                    Task { await attemptBiometricUnlock() }
                } label: {
                    if isAuthenticatingBiometric {
                        ProgressView()
                    } else {
                        Label(biometricLabel, systemImage: biometricSystemImage)
                    }
                }
                .disabled(isAuthenticatingBiometric)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            if AppLockStore.isBiometricEnabled {
                await attemptBiometricUnlock()
            }
        }
    }

    private func attemptUnlock() {
        if AppLockStore.verify(password) {
            onUnlock()
        } else {
            errorMessage = "密码不正确"
            password = ""
        }
    }

    private func attemptBiometricUnlock() async {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evaluationError) else { return }
        isAuthenticatingBiometric = true
        defer { isAuthenticatingBiometric = false }
        let succeeded = (try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, localizedReason: "解锁阅读"
        )) ?? false
        if succeeded {
            onUnlock()
        }
    }

    /// `LAContext.biometryType` only reads back reliably *after* `canEvaluatePolicy` has been
    /// called on that exact context instance -- querying it on a fresh, never-evaluated context is
    /// a known source of it reporting `.none` even on a Face ID device. Both label/icon reads route
    /// through this one evaluated context rather than each constructing their own.
    private var evaluatedContext: LAContext {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context
    }

    private var biometricLabel: String {
        evaluatedContext.biometryType == .faceID ? "使用面容 ID 解锁" : "使用指纹解锁"
    }

    private var biometricSystemImage: String {
        evaluatedContext.biometryType == .faceID ? "faceid" : "touchid"
    }
}
