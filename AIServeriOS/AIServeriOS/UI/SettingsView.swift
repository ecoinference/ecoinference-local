import SwiftUI

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState

    @State private var portText   = ""
    @State private var hfToken    = ""
    @State private var useGpu     = false
    @State private var autoStart  = false
    @State private var showToken  = false

    private let settings = SettingsService.shared

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                authSection
                inferenceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear { load() }
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section {
            HStack {
                Text("Port")
                Spacer()
                TextField("8080", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            Toggle("Auto-start on launch", isOn: $autoStart)
        } header: {
            Text("Server")
        } footer: {
            Text("Restart the server after changing the port.")
        }
    }

    private var authSection: some View {
        Section {
            HStack {
                if showToken {
                    TextField("hf_…", text: $hfToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("hf_…", text: $hfToken)
                }
                Spacer()
                Button { showToken.toggle() } label: {
                    Image(systemName: showToken ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("HuggingFace Token")
        } footer: {
            Text("Required to download gated Gemma models. Get one at huggingface.co/settings/tokens")
        }
    }

    private var inferenceSection: some View {
        Section {
            Toggle("Use GPU (Metal)", isOn: $useGpu)
        } header: {
            Text("Inference")
        } footer: {
            Text("GPU acceleration requires unloading and reloading the model.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("API", value: "OpenAI-compatible REST")
            LabeledContent("Runtime", value: "LiteRT-LM 0.10.2")
        }
    }

    // MARK: - Load / save

    private func load() {
        portText  = String(settings.serverPort)
        hfToken   = settings.hfToken
        useGpu    = settings.useGpu
        autoStart = settings.autoStart
    }

    private func save() {
        if let port = UInt16(portText) { settings.serverPort = port }
        settings.hfToken   = hfToken
        settings.useGpu    = useGpu
        settings.autoStart = autoStart
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
