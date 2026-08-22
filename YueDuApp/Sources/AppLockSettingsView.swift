import SwiftUI
import LocalAuthentication

/// Set/change/remove the local app-access password (`AppLockStore`). Changing or disabling
/// requires re-entering the current password -- forgetting it means there's no recovery path
/// (this is a local-only device PIN, not an account with a reset flow), which is the same
/// trade-off Legado's own app-lock makes.
struct AppLockSettingsView: View {
    @State private var isEnabled = AppLockStore.isEnabled
    @State private var isBiometricEnabled = AppLockStore.isBiometricEnabled
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?

    /// `nil` when this device has no enrolled Face ID/Touch ID at all -- the toggle is hidden
    /// rather than shown-disabled in that case, matching how the OS's own Settings app treats it.
    private var biometryType: LABiometryType? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        return context.biometryType
    }

    var body: some View {
        Form {
            if isEnabled {
                Section {
                    Label("密码锁已开启", systemImage: "lock.fill").foregroundStyle(.green)
                    if let biometryType {
                        Toggle(biometryType == .faceID ? "允许面容 ID 解锁" : "允许指纹解锁", isOn: Binding(
                            get: { isBiometricEnabled },
                            set: { newValue in
                                isBiometricEnabled = newValue
                                AppLockStore.setBiometricEnabled(newValue)
                            }
                        ))
                    }
                }
                Section("修改密码") {
                    SecureField("当前密码", text: $currentPassword)
                    SecureField("新密码", text: $newPassword)
                    SecureField("确认新密码", text: $confirmPassword)
                    Button("保存新密码") { changePassword() }
                        .disabled(currentPassword.isEmpty || newPassword.isEmpty)
                }
                Section {
                    Button("关闭密码锁", role: .destructive) { disable() }
                        .disabled(currentPassword.isEmpty)
                }
            } else {
                Section("设置密码") {
                    SecureField("新密码", text: $newPassword)
                    SecureField("确认新密码", text: $confirmPassword)
                    Button("开启密码锁") { enable() }
                        .disabled(newPassword.isEmpty)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            if let successMessage {
                Text(successMessage).font(.caption).foregroundStyle(.green)
            }
        }
        .navigationTitle("本地密码锁")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func enable() {
        errorMessage = nil
        successMessage = nil
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            return
        }
        AppLockStore.setPassword(newPassword)
        isEnabled = true
        newPassword = ""
        confirmPassword = ""
        successMessage = "密码锁已开启"
    }

    private func changePassword() {
        errorMessage = nil
        successMessage = nil
        guard AppLockStore.verify(currentPassword) else {
            errorMessage = "当前密码不正确"
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的新密码不一致"
            return
        }
        AppLockStore.setPassword(newPassword)
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
        successMessage = "密码已更新"
    }

    private func disable() {
        errorMessage = nil
        successMessage = nil
        guard AppLockStore.verify(currentPassword) else {
            errorMessage = "当前密码不正确"
            return
        }
        AppLockStore.disable()
        isEnabled = false
        isBiometricEnabled = false
        currentPassword = ""
        successMessage = "密码锁已关闭"
    }
}
