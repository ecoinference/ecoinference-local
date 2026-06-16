import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showCreateAccount = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                EcoColors.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(EcoColors.green)
                        Text("EcoInference")
                            .font(.largeTitle.bold())
                        Text("On-device AI")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await signIn() }
                        } label: {
                            if isLoading {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Sign In").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EcoColors.green)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                    }
                    .padding(.horizontal, 28)

                    HStack {
                        Button("Forgot Password?") { showForgotPassword = true }
                            .font(.footnote)
                        Spacer()
                        Button("Create Account") { showCreateAccount = true }
                            .font(.footnote)
                    }
                    .foregroundStyle(EcoColors.green)
                    .padding(.horizontal, 28)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView()
                .environmentObject(authService)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .environmentObject(authService)
        }
    }

    private func signIn() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            try await authService.signIn(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
