import SwiftUI

/// Full-screen gate shown before any app content when a local access password is configured --
/// calls `onUnlock` the moment verification succeeds. No attempt-count lockout or Face ID fallback
/// in this first increment; those are reasonable follow-ups, not required for the core "someone
/// picks up my unlocked phone" threat this protects against.
struct AppLockView: View {
    let onUnlock: () -> Void

    @State private var password = ""
    @State private var errorMessage: String?

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func attemptUnlock() {
        if AppLockStore.verify(password) {
            onUnlock()
        } else {
            errorMessage = "密码不正确"
            password = ""
        }
    }
}
