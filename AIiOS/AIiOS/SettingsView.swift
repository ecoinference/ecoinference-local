import SwiftUI

struct SettingsView: View {

    @ObservedObject private var settings = SettingsService.shared

    var body: some View {
        NavigationStack {
            Form {

                // ── Model ─────────────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Max tokens")
                        Spacer()
                        Text("\(settings.maxNumTokens)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxNumTokens) },
                            set: { settings.maxNumTokens = Int($0) }
                        ),
                        in: 512...8192,
                        step: 512
                    )
                } header: {
                    Text("Inference")
                } footer: {
                    Text("KV-cache budget shared between prompt, history, and response. Higher values use more RAM.")
                }

                // ── System prompt ─────────────────────────────────────────────
                Section {
                    TextEditor(text: Binding(
                        get: { settings.systemPrompt ?? "" },
                        set: { settings.systemPrompt = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 80)
                    .font(.body)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Optional. Applied to every conversation. Leave blank to use the model default.")
                }

                // ── Cloud AI (router) ────────────────────────────────────────
                Section {
                    SecureField("Gemini API key", text: $settings.geminiApiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Link("Get a free API key at aistudio.google.com",
                         destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                } header: {
                    Text("Cloud AI")
                } footer: {
                    Text("Used by the router for requests that need a more capable cloud model. Local on-device inference always works without this key.")
                }

                // ── Tests ────────────────────────────────────────────────────
                Section {
                    NavigationLink(destination: TestView()) {
                        Label("Inference Tests", systemImage: "checkmark.seal")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Run smoke tests against the loaded model to verify inference, multi-turn context, and vision.")
                }

                // ── About ─────────────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("URL scheme", value: "ecoinference://")
                }
            }
            .scrollContentBackground(.hidden)
            .background(EcoColors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
