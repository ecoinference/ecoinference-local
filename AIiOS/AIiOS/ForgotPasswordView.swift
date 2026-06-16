import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var sent = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                EcoColors.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    if sent {
                        VStack(spacing: 16) {
                            Image(systemName: "envelope.badge.checkmark.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(EcoColors.green)
                            Text("Check your email")
                                .font(.title2.bold())
                            Text("A reset link was sent to \(email).")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 28)
                    } else {
                        VStack(spacing: 14) {
                            Text("Enter your email address and we'll send a password reset link.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)

                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.roundedBorder)

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                Task { await sendReset() }
                            } label: {
                                if isLoading {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Text("Send Reset Email").frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(EcoColors.green)
                            .disabled(email.isEmpty || isLoading)
                        }
                        .padding(.horizontal, 28)
                    }
                    Spacer()
                    if sent {
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(EcoColors.green)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !sent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private func sendReset() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            try await authService.sendPasswordReset(to: email.trimmingCharacters(in: .whitespaces))
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
