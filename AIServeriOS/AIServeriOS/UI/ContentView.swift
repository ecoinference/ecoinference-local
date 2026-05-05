import SwiftUI

struct ContentView: View {

    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                serverSection
                modelsSection
            }
            .navigationTitle("AI Server")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(state)
            }
            .onAppear {
                state.refreshCatalog()
                if SettingsService.shared.autoStart {
                    state.startServer()
                }
            }
        }
    }

    // MARK: - Server section

    private var serverSection: some View {
        Section("Server") {
            HStack {
                Circle()
                    .fill(state.serverRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(state.serverRunning
                     ? "Running on port \(state.serverPort)"
                     : "Stopped")
                    .foregroundStyle(.primary)
                Spacer()
                Button(state.serverRunning ? "Stop" : "Start") {
                    if state.serverRunning { state.stopServer() }
                    else                   { state.startServer() }
                }
                .buttonStyle(.borderedProminent)
                .tint(state.serverRunning ? .red : .green)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Models section

    private var modelsSection: some View {
        Section("Models") {
            ForEach(state.models) { model in
                ModelRow(model: model)
                    .environmentObject(state)
            }
        }
    }
}

// MARK: - ModelRow

private struct ModelRow: View {

    let model: ModelInfo
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            // Download progress bar
            if state.downloadActive && state.downloadingModelId == model.id {
                ProgressView(value: state.downloadProgress, total: 100)
                    .animation(.linear, value: state.downloadProgress)
                Text(String(format: "%.0f%%", state.downloadProgress))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Download error — only show on the row whose download failed
            if let err = state.downloadError, state.downloadErrorModelId == model.id {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Load error — only show on the row whose load actually failed
            if let err = state.loadError, state.loadErrorModelId == model.id {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Action buttons
            HStack(spacing: 8) {
                Spacer()
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if model.loaded {
            Label("Loaded", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if model.downloaded {
            Label("Ready", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        } else {
            Label("Not downloaded", systemImage: "icloud.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if !model.downloaded {
            // Download
            if state.downloadActive && state.downloadingModelId == model.id {
                Button("Cancel") { state.cancelDownload() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.orange)
            } else {
                Button("Download") { state.startDownload(modelId: model.id) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(state.downloadActive)
            }
        } else if model.loaded {
            Button("Unload") { state.unloadModel() }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.orange)
        } else {
            Button(state.isLoading ? "Loading…" : "Load") {
                state.loadModel(modelId: model.id,
                                useGpu: SettingsService.shared.useGpu)
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .disabled(state.isLoading)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
