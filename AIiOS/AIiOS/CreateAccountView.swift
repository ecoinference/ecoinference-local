import SwiftUI

struct CreateAccountView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var usernameStatus: UsernameCheckStatus = .idle
    @State private var errorMessage = ""
    @State private var isLoading = false

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }
    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && !passwordMismatch
        && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        && usernameStatus == .available && !isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EcoColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Group {
                            TextField("Display Name", text: $displayName)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)

                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Username (4–16 chars, lowercase)", text: $username)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: username) { _, raw in
                                        let norm = UsernameValidator.normalized(raw)
                                        if username != norm { username = norm }
                                        validateUsername(norm)
                                    }
                                if let msg = usernameStatus.message {
                                    Text(msg)
                                        .font(.caption)
                                        .foregroundStyle(usernameStatus.color)
                                }
                            }

                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            SecureField("Password (min 8 chars)", text: $password)
                                .textContentType(.newPassword)

                            VStack(alignment: .leading, spacing: 4) {
                                SecureField("Confirm Password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                if passwordMismatch {
                                    Text("Passwords don't match")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await createAccount() }
                        } label: {
                            if isLoading {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Create Account").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EcoColors.green)
                        .disabled(!canSubmit)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validateUsername(_ name: String) {
        do {
            try UsernameValidator.validate(name)
        } catch let e as UsernameValidator.ValidationError {
            usernameStatus = .invalid(e.localizedDescription ?? "Invalid")
            return
        } catch {}
        usernameStatus = .checking
        Task {
            do {
                let available = try await UserProfileService.shared.isUsernameAvailable(name)
                usernameStatus = available ? .available : .taken
            } catch {
                usernameStatus = .idle
            }
        }
    }

    private func createAccount() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            let user = try await authService.createAccount(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            try await UserProfileService.shared.createProfile(
                uid: user.uid,
                email: email.trimmingCharacters(in: .whitespaces),
                username: username,
                displayName: displayName.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Username check state

enum UsernameCheckStatus: Equatable {
    case idle, checking, available, taken, invalid(String)

    var color: Color {
        switch self {
        case .available: return .green
        case .taken, .invalid: return .red
        default: return .secondary
        }
    }
    var message: String? {
        switch self {
        case .available:       return "Username is available"
        case .taken:           return "Username is already taken"
        case .checking:        return "Checking…"
        case .invalid(let m):  return m
        case .idle:            return nil
        }
    }
}
