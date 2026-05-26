import SwiftUI

struct ModelsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var showDeleteConfirm: ModelInfo? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.models) { model in
                    ModelRow(model: model)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { appState.refreshCatalog() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            // ── Download progress banner ──────────────────────────────────────
            .safeAreaInset(edge: .bottom) {
                if appState.downloadActive {
                    downloadBanner
                }
            }
        }
    }

    // MARK: - Download banner

    private var downloadBanner: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Downloading \(appState.downloadingModelId ?? "model")…")
                    .font(.footnote)
                Spacer()
                Button("Cancel") { appState.cancelDownload() }
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            ProgressView(value: appState.downloadProgress, total: 100)
                .progressViewStyle(.linear)
            Text(String(format: "%.0f%%", appState.downloadProgress))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
    }
}

// MARK: - ModelRow

private struct ModelRow: View {

    @EnvironmentObject private var appState: AppState
    let model: ModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Header ────────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                statusBadge
            }

            // ── Load error ────────────────────────────────────────────────────
            if appState.loadErrorModelId == model.id,
               let err = appState.loadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // ── Download error ────────────────────────────────────────────────
            if appState.downloadErrorModelId == model.id,
               let err = appState.downloadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // ── Action buttons ────────────────────────────────────────────────
            HStack(spacing: 10) {
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Status badge

    @ViewBuilder private var statusBadge: some View {
        if model.loaded {
            Label("Loaded", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if appState.isLoading && appState.loadErrorModelId == nil {
            Label("Loading…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if model.downloaded {
            Label("Ready", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        } else {
            Label("Not downloaded", systemImage: "icloud.and.arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Action buttons

    @ViewBuilder private var actionButtons: some View {
        if model.loaded {
            // Unload
            Button(role: .destructive) {
                appState.unloadModel()
            } label: {
                Label("Unload", systemImage: "eject")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

        } else if appState.isLoading {
            // Busy — show spinner, no action
            ProgressView()
                .scaleEffect(0.8)

        } else if model.downloaded {
            // Load
            Button {
                appState.loadModel(modelId: model.id)
            } label: {
                Label("Load", systemImage: "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)

            // Delete
            Button(role: .destructive) {
                appState.deleteModel(modelId: model.id)
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

        } else if appState.downloadActive && appState.downloadingModelId == model.id {
            // This model is downloading — cancel handled by banner
            Text("Downloading…")
                .font(.caption)
                .foregroundStyle(.secondary)

        } else {
            // Download
            Button {
                appState.startDownload(modelId: model.id)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.downloadActive)
        }
    }
}
