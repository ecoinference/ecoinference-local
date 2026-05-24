import SwiftUI
import UIKit

// MARK: - Test model

private enum TestStatus { case pending, running, passed, failed }
private enum TestCategory { case model, inference, vision }

private struct TestCase: Identifiable {
    let id:          String
    let name:        String
    let description: String
    let category:    TestCategory
    /// If nil this is a direct (non-LLM) test; if non-nil it's the message
    /// list sent to InferenceService.
    let messages:    [InferenceMessage]?
    /// All of these strings must appear in the result (case-insensitive).
    var mustContain:    [String] = []
    /// None of these strings may appear in the result.
    var mustNotContain: [String] = []

    var isE2E: Bool { messages != nil }
}

private class TestResult: ObservableObject, Identifiable {
    let testCase: TestCase
    var id: String { testCase.id }
    @Published var status:  TestStatus = .pending
    @Published var detail:  String     = ""
    @Published var elapsed: TimeInterval?

    init(_ tc: TestCase) { testCase = tc }
}

// MARK: - Test registry

private func buildCases(isMultimodal: Bool) -> [TestCase] {
    var cases: [TestCase] = [

        // ── Direct: model state ────────────────────────────────────────────────
        TestCase(
            id: "model_loaded",
            name: "Model — is loaded",
            description: "InferenceService.isLoaded == true",
            category: .model,
            messages: nil
        ),
        TestCase(
            id: "model_has_id",
            name: "Model — loadedModelId is set",
            description: "loadedModelId is non-nil and non-empty",
            category: .model,
            messages: nil
        ),

        // ── E2E: basic arithmetic ──────────────────────────────────────────────
        TestCase(
            id: "e2e_math",
            name: "Inference — basic arithmetic",
            description: "\"12 × 12\" → response contains \"144\"",
            category: .inference,
            messages: [InferenceMessage(role: "user",
                                        text: "What is 12 multiplied by 12? Reply with just the number.")],
            mustContain: ["144"]
        ),

        // ── E2E: factual recall ────────────────────────────────────────────────
        TestCase(
            id: "e2e_capital",
            name: "Inference — factual recall",
            description: "\"Capital of France\" → response contains \"Paris\"",
            category: .inference,
            messages: [InferenceMessage(role: "user",
                                        text: "What is the capital of France? Reply with just the city name.")],
            mustContain: ["Paris"]
        ),

        // ── E2E: no stray tokens ───────────────────────────────────────────────
        TestCase(
            id: "e2e_no_end_token",
            name: "Inference — no stray end-of-turn token",
            description: "Response must not expose <end_of_turn>",
            category: .inference,
            messages: [InferenceMessage(role: "user",
                                        text: "Say hello in three words.")],
            mustNotContain: ["<end_of_turn>", "<start_of_turn>"]
        ),

        // ── E2E: non-empty response ────────────────────────────────────────────
        TestCase(
            id: "e2e_non_empty",
            name: "Inference — response is non-empty",
            description: "Model produces at least 1 character of output",
            category: .inference,
            messages: [InferenceMessage(role: "user",
                                        text: "Reply with the single word \"OK\".")]
        ),

        // ── E2E: multi-turn memory ─────────────────────────────────────────────
        TestCase(
            id: "e2e_multiturn",
            name: "Inference — multi-turn context",
            description: "Turn 1 establishes fact; turn 2 recalls it → \"42\"",
            category: .inference,
            messages: [
                InferenceMessage(role: "user",
                                 text: "My lucky number is 42. Remember it."),
                InferenceMessage(role: "assistant",
                                 text: "Got it! Your lucky number is 42."),
                InferenceMessage(role: "user",
                                 text: "What is my lucky number? Reply with just the number."),
            ],
            mustContain: ["42"]
        ),
    ]

    // ── Vision (multimodal only) ─────────────────────────────────────────────
    if isMultimodal {
        cases.append(TestCase(
            id: "e2e_vision",
            name: "Vision — describe test image",
            description: "4-colour 64×64 grid → non-empty description, no error",
            category: .vision,
            messages: [InferenceMessage(role: "user",
                                        text: "Describe this image in one sentence.")],
            mustNotContain: ["[ERROR"]
        ))
    }

    return cases
}

// MARK: - TestView

struct TestView: View {

    @EnvironmentObject private var appState: AppState

    @State private var results: [TestResult] = []
    @State private var running   = false
    @State private var currentId: String? = nil
    @State private var runTask:  Task<Void,Never>? = nil

    private var passed: Int { results.filter { $0.status == .passed }.count }
    private var failed: Int { results.filter { $0.status == .failed }.count }

    // Build (or rebuild) the result list whenever the view appears or the
    // model changes.
    private func buildResults() {
        let isMulti = InferenceService.shared.isMultimodal
        let cases   = buildCases(isMultimodal: isMulti)
        // Preserve prior pass/fail state if the same IDs already exist
        let existing = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        results = cases.map { existing[$0.id] ?? TestResult($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            testList
        }
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if running {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else {
                    Button {
                        runAll()
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 20))
                    }
                    .disabled(!appState.modelLoaded)
                    .help("Run all tests")
                }
            }
        }
        .onAppear { buildResults() }
    }

    // MARK: Summary bar

    private var summaryBar: some View {
        HStack(spacing: 8) {
            badge("\(passed) passed", color: .green)
            badge("\(failed) failed", color: failed > 0 ? .red : .secondary)
            Text("of \(results.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !appState.modelLoaded {
                Label("No model loaded", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: Test list

    private var testList: some View {
        List(results) { r in
            TestTile(result: r, isRunning: running && currentId == r.id)
        }
        .listStyle(.plain)
    }

    // MARK: - Run all

    private func runAll() {
        guard !running, appState.modelLoaded else { return }

        // Reset all results
        for r in results {
            r.status  = .pending
            r.detail  = ""
            r.elapsed = nil
        }
        running = true

        runTask = Task {
            for result in results {
                guard !Task.isCancelled else { break }
                await MainActor.run { currentId = result.id }
                await run(result)
            }
            // Clean up: reset the engine so ChatView's next conversation
            // isn't treated as a continuation of the last test's KV-cache state.
            InferenceService.shared.resetConversation()
            await MainActor.run { running = false; currentId = nil }
        }
    }

    // MARK: - Run one

    @MainActor
    private func run(_ r: TestResult) async {
        r.status = .running
        let start = Date()

        do {
            let detail = try await execute(r.testCase)
            r.elapsed = Date().timeIntervalSince(start)
            evaluate(r, detail: detail)
        } catch {
            r.elapsed = Date().timeIntervalSince(start)
            r.status  = .failed
            r.detail  = "Exception: \(error.localizedDescription)"
        }
    }

    // MARK: - Execute one test

    private func execute(_ tc: TestCase) async throws -> String {
        // Direct tests (no LLM)
        if tc.messages == nil {
            return try executeDirect(tc)
        }

        // E2E: vision test needs a test image injected
        var messages = tc.messages!
        if tc.id == "e2e_vision" {
            guard let imageData = makeTestImageData() else {
                throw RunError.imageGenerationFailed
            }
            // Replace the user message to include raw image data
            messages = [InferenceMessage(role: "user",
                                         text: tc.messages!.last!.text,
                                         imageData: imageData)]
        }

        // E2E: each test is isolated — reset the KV-cache committed-count so the
        // engine treats this as a fresh turn 1 rather than an incremental continuation
        // of whatever the previous test left behind.
        InferenceService.shared.resetConversation()

        return try await Task.detached(priority: .userInitiated) {
            try InferenceService.shared.chat(
                messages: messages,
                maxTokens: 256,
                temperature: 0.1   // low temp for deterministic test results
            )
        }.value
    }

    private func executeDirect(_ tc: TestCase) throws -> String {
        switch tc.id {
        case "model_loaded":
            let loaded = InferenceService.shared.isLoaded
            if !loaded { throw RunError.modelNotLoaded }
            return "isLoaded = true ✓"

        case "model_has_id":
            guard let mid = InferenceService.shared.loadedModelId, !mid.isEmpty else {
                throw RunError.noModelId
            }
            return "loadedModelId = \"\(mid)\" ✓"

        default:
            throw RunError.unknownDirectTest(tc.id)
        }
    }

    // MARK: - Evaluate

    private func evaluate(_ r: TestResult, detail: String) {
        let lower = detail.lowercased()

        // mustContain checks (case-insensitive)
        for kw in r.testCase.mustContain {
            if !lower.contains(kw.lowercased()) {
                r.status = .failed
                r.detail = "Expected \"\(kw)\" not found in:\n\(detail)"
                return
            }
        }

        // mustNotContain checks
        for kw in r.testCase.mustNotContain {
            if lower.contains(kw.lowercased()) {
                r.status = .failed
                r.detail = "Unexpected \"\(kw)\" found in:\n\(detail)"
                return
            }
        }

        // Non-empty check for inference tests
        if r.testCase.isE2E && detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.status = .failed
            r.detail = "Model returned an empty response."
            return
        }

        r.status = .passed
        r.detail = detail.count > 300 ? "\(detail.prefix(300))…" : detail
    }

    // MARK: - Test image (4-colour 64×64 grid)

    private func makeTestImageData() -> Data? {
        let size = CGSize(width: 64, height: 64)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        let colours: [(CGRect, UIColor)] = [
            (CGRect(x:  0, y:  0, width: 32, height: 32), .red),
            (CGRect(x: 32, y:  0, width: 32, height: 32), .green),
            (CGRect(x:  0, y: 32, width: 32, height: 32), .blue),
            (CGRect(x: 32, y: 32, width: 32, height: 32), .yellow),
        ]
        for (rect, colour) in colours {
            ctx.setFillColor(colour.cgColor)
            ctx.fill(rect)
        }
        return UIGraphicsGetImageFromCurrentImageContext()?.pngData()
    }
}

// MARK: - Errors

private enum RunError: LocalizedError {
    case modelNotLoaded
    case noModelId
    case imageGenerationFailed
    case unknownDirectTest(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:          return "Model is not loaded."
        case .noModelId:               return "No model ID found."
        case .imageGenerationFailed:   return "Could not generate test image."
        case .unknownDirectTest(let i): return "Unknown direct test: \(i)"
        }
    }
}

// MARK: - TestTile

private struct TestTile: View {

    @ObservedObject var result: TestResult
    let isRunning: Bool

    var body: some View {
        DisclosureGroup {
            if !result.detail.isEmpty {
                Text(result.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(result.status == .failed ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        } label: {
            HStack(spacing: 10) {
                // Status icon / spinner
                if isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .frame(width: 20, height: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        categoryChip
                        if result.testCase.isE2E { e2eChip }
                        Text(result.testCase.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(result.status == .failed ? .red : .primary)
                    }
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var subtitleText: String {
        if let ms = result.elapsed {
            return "\(result.testCase.description)  ·  \(Int(ms * 1000)) ms"
        }
        return result.testCase.description
    }

    private var statusIcon: String {
        switch result.status {
        case .pending: return "circle"
        case .running: return "hourglass"
        case .passed:  return "checkmark.circle"
        case .failed:  return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .pending: return .secondary
        case .running: return .accentColor
        case .passed:  return .green
        case .failed:  return .red
        }
    }

    private var categoryChip: some View {
        let (label, color): (String, Color) = switch result.testCase.category {
        case .model:     ("Model",     .blue)
        case .inference: ("Inference", .purple)
        case .vision:    ("Vision",    .teal)
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var e2eChip: some View {
        Text("E2E")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
