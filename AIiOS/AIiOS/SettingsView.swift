import SwiftUI

struct SettingsView: View {

    @ObservedObject private var settings  = SettingsService.shared
    @ObservedObject private var router    = RouterService.shared

    @State private var refreshing         = false
    @State private var refreshMsg: String = ""

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

                // ── Developer ────────────────────────────────────────────────
                Section {
                    NavigationLink(destination: TestView()) {
                        Label("Inference Tests", systemImage: "flask")
                    }

                    // Router Rules refresh
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Router Rules", systemImage: "cloud")
                            .font(.body)
                        Text("Active rule set version: \(router.ruleSet.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !refreshMsg.isEmpty {
                            Text(refreshMsg)
                                .font(.caption)
                                .foregroundStyle(refreshMsg.hasPrefix("Updated") ? EcoColors.green : .secondary)
                        }
                        Button {
                            Task {
                                refreshing = true
                                refreshMsg = ""
                                let result = await RouterService.shared.refreshFromRemote()
                                switch result {
                                case .updated(let v):       refreshMsg = "Updated to version \(v)"
                                case .alreadyCurrent(let v): refreshMsg = "Already current (v\(v))"
                                case .noRemoteValue:        refreshMsg = "No rules published in Remote Config yet"
                                case .error(let msg):       refreshMsg = "Error: \(msg)"
                                }
                                refreshing = false
                            }
                        } label: {
                            if refreshing {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Refreshing…")
                                }
                            } else {
                                Label("Refresh from Remote Config", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EcoColors.green)
                        .disabled(refreshing)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Inference Tests run smoke tests against the loaded model. Router Rules pulls the latest routing config from Firebase Remote Config.")
                }

                // ── About ─────────────────────────────────────────────────────
                Section {
                    VStack(spacing: 6) {
                        Text("🌿")
                            .font(.system(size: 40))
                        Text("EcoInference")
                            .font(.headline)
                        Text("Local AI, offline and private.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Local inference", value: "Google LiteRT-LM")
                    LabeledContent("URL scheme", value: "ecoinference://")
                } header: {
                    Text("About")
                } footer: {
                    Text("© \(Calendar.current.component(.year, from: Date())) EcoInference")
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
