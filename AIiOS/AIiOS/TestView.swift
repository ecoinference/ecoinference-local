import SwiftUI
import UIKit

// MARK: - Test model

private enum TestStatus { case pending, running, passed, failed, skipped }
private enum TestCategory { case model, inference, vision, python }

/// Expected result kind for Python and E2E tests.
private enum ResultKind { case text, image, html }

private struct TestCase: Identifiable {
    let id:          String
    let name:        String
    let description: String
    let category:    TestCategory

    // ── Inference E2E (non-Python) ────────────────────────────────────────────
    /// If non-nil, sent to InferenceService.chat() directly (no agent loop).
    let messages:    [InferenceMessage]?

    // ── Python direct ─────────────────────────────────────────────────────────
    /// Python code to run via PythonRunner.execute().
    let pythonCode:  String?

    // ── Python E2E ────────────────────────────────────────────────────────────
    /// User prompt for the full agent loop (Python E2E).
    let e2ePrompt:   String?

    // ── Evaluation ────────────────────────────────────────────────────────────
    var expectedKind:   ResultKind = .text
    var altKind:        ResultKind? = nil
    var mustContain:    [String]   = []
    var mustNotContain: [String]   = []

    // ── Availability ──────────────────────────────────────────────────────────
    /// If true, the test is shown but not run (e.g. dependency not available).
    var isSkipped:   Bool = false
    var skipReason:  String = ""

    // ── GPS ───────────────────────────────────────────────────────────────────
    /// Prepend GPS variables before running pythonCode.
    /// Declared last so it can be omitted from memberwise init without
    /// disrupting other trailing defaults.
    var gpsPreamble: Bool = false

    // ── Computed ──────────────────────────────────────────────────────────────
    var isInferenceE2E: Bool { messages != nil }
    var isPythonDirect: Bool { pythonCode != nil && e2ePrompt == nil }
    var isPythonE2E:    Bool { e2ePrompt  != nil }

    func accepts(_ kind: ResultKind) -> Bool {
        kind == expectedKind || (altKind != nil && kind == altKind!)
    }
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
            id:          "model_loaded",
            name:        "Model — is loaded",
            description: "InferenceService.isLoaded == true",
            category:    .model,
            messages:    nil, pythonCode: nil, e2ePrompt: nil
        ),
        TestCase(
            id:          "model_has_id",
            name:        "Model — loadedModelId is set",
            description: "loadedModelId is non-nil and non-empty",
            category:    .model,
            messages:    nil, pythonCode: nil, e2ePrompt: nil
        ),

        // ── E2E: basic arithmetic ──────────────────────────────────────────────
        TestCase(
            id:          "e2e_math",
            name:        "Inference — basic arithmetic",
            description: "\"12 × 12\" → response contains \"144\"",
            category:    .inference,
            messages:    [InferenceMessage(role: "user",
                                           text: "What is 12 multiplied by 12? Reply with just the number.")],
            pythonCode:  nil, e2ePrompt: nil,
            mustContain: ["144"]
        ),

        // ── E2E: factual recall ────────────────────────────────────────────────
        TestCase(
            id:          "e2e_capital",
            name:        "Inference — factual recall",
            description: "\"Capital of France\" → response contains \"Paris\"",
            category:    .inference,
            messages:    [InferenceMessage(role: "user",
                                           text: "What is the capital of France? Reply with just the city name.")],
            pythonCode:  nil, e2ePrompt: nil,
            mustContain: ["Paris"]
        ),

        // ── E2E: no stray tokens ───────────────────────────────────────────────
        TestCase(
            id:             "e2e_no_end_token",
            name:           "Inference — no stray end-of-turn token",
            description:    "Response must not expose <end_of_turn>",
            category:       .inference,
            messages:       [InferenceMessage(role: "user", text: "Say hello in three words.")],
            pythonCode:     nil, e2ePrompt: nil,
            mustNotContain: ["<end_of_turn>", "<start_of_turn>"]
        ),

        // ── E2E: non-empty response ────────────────────────────────────────────
        TestCase(
            id:          "e2e_non_empty",
            name:        "Inference — response is non-empty",
            description: "Model produces at least 1 character of output",
            category:    .inference,
            messages:    [InferenceMessage(role: "user", text: "Reply with the single word \"OK\".")],
            pythonCode:  nil, e2ePrompt: nil
        ),

        // ── E2E: multi-turn memory ─────────────────────────────────────────────
        TestCase(
            id:          "e2e_multiturn",
            name:        "Inference — multi-turn context",
            description: "Turn 1 establishes fact; turn 2 recalls it → \"42\"",
            category:    .inference,
            messages:    [
                InferenceMessage(role: "user",
                                 text: "My lucky number is 42. Remember it."),
                InferenceMessage(role: "assistant",
                                 text: "Got it! Your lucky number is 42."),
                InferenceMessage(role: "user",
                                 text: "What is my lucky number? Reply with just the number."),
            ],
            pythonCode: nil, e2ePrompt: nil,
            mustContain: ["42"]
        ),

        // ── Python: NumPy sqrt sum ─────────────────────────────────────────────
        TestCase(
            id:           "numpy_sqrt_sum",
            name:         "NumPy — sqrt sum",
            description:  "sqrt([1,4,9,16,25]).sum() == 15.0",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import numpy as np
arr = np.array([1, 4, 9, 16, 25])
result = str(round(float(np.sqrt(arr).sum()), 4))
""",
            e2ePrompt:    nil,
            expectedKind: .text,
            mustContain:  ["15"]
        ),

        // ── Python: SciPy normal PDF ───────────────────────────────────────────
        TestCase(
            id:          "scipy_norm_pdf",
            name:        "SciPy — normal PDF",
            description: "Not available on iOS",
            category:    .python,
            messages:    nil, pythonCode: nil, e2ePrompt: nil,
            isSkipped:   true,
            skipReason:  "scipy is not available on iOS"
        ),

        // ── Python: Pandas mean ────────────────────────────────────────────────
        TestCase(
            id:           "pandas_mean",
            name:         "Pandas — DataFrame mean",
            description:  "Mean of [1,2,3,4,5] == 3.0",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import pandas as pd
df = pd.DataFrame({'values': [1, 2, 3, 4, 5]})
result = str(float(df['values'].mean()))
""",
            e2ePrompt:    nil,
            expectedKind: .text,
            mustContain:  ["3.0"]
        ),

        // ── Python: Matplotlib sine wave ───────────────────────────────────────
        TestCase(
            id:           "matplotlib_sine",
            name:         "Matplotlib — sine wave PNG",
            description:  "sin(x) 0→2π → PNG image result",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import numpy as np
import matplotlib.pyplot as plt
x = np.linspace(0, 2 * 3.14159265, 200)
plt.figure(figsize=(6, 3))
plt.plot(x, np.sin(x), color='steelblue')
plt.title('Sine Wave')
plt.xlabel('x')
plt.ylabel('sin(x)')
""",
            e2ePrompt:    nil,
            expectedKind: .image
        ),

        // ── Python: Plotly Express bar ─────────────────────────────────────────
        TestCase(
            id:           "plotly_express_bar",
            name:         "Plotly Express — bar chart",
            description:  "Bar chart → interactive HTML",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import plotly.express as px
fig = px.bar(
    x=['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon'],
    y=[10, 25, 15, 30, 20],
    title='Test Bar Chart')
result = fig.to_html(include_plotlyjs='cdn', full_html=True)
""",
            e2ePrompt:    nil,
            expectedKind: .html
        ),

        // ── Python: Plotly Graph Objects scatter ───────────────────────────────
        TestCase(
            id:           "plotly_go_scatter",
            name:         "Plotly GO — scatter chart",
            description:  "Scatter via graph_objects → interactive HTML",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import plotly.graph_objects as go
fig = go.Figure(go.Scatter(
    x=[1, 2, 3, 4, 5],
    y=[2, 4, 1, 5, 3],
    mode='markers+lines'))
fig.update_layout(title='Test Scatter')
result = fig.to_html(include_plotlyjs='cdn', full_html=True)
""",
            e2ePrompt:    nil,
            expectedKind: .html
        ),

        // ── Python: Astral sunrise / sunset ───────────────────────────────────
        TestCase(
            id:           "astral_sunrise",
            name:         "Astral — sunrise / sunset",
            description:  "Sunrise & sunset at device GPS location today",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import datetime
from astral import LocationInfo
from astral.sun import sun

location = LocationInfo(
    name='Device', region='GPS', timezone=user_timezone,
    latitude=user_latitude, longitude=user_longitude)
today = datetime.date.today()
s = sun(location.observer, date=today, tzinfo=datetime.timezone.utc)
result = (
    f"Sunrise: {s['sunrise'].strftime('%I:%M %p')}\\n"
    f"Sunset:  {s['sunset'].strftime('%I:%M %p')}\\n"
    f"Noon:    {s['noon'].strftime('%I:%M %p')}"
)
""",
            e2ePrompt:    nil,
            expectedKind: .text,
            mustContain:  [":"],
            gpsPreamble:  true
        ),

        // ── Python: Astral moon phase ──────────────────────────────────────────
        TestCase(
            id:           "astral_moon",
            name:         "Astral — moon phase",
            description:  "Moon phase today as float 0–28 with phase name",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import datetime
from astral.moon import phase

today = datetime.date.today()
p = phase(today)
names = ['New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
         'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent']
idx = int(p / 3.5) % 8
result = f"Moon phase: {p:.1f}/28 — {names[idx]}"
""",
            e2ePrompt:    nil,
            expectedKind: .text,
            mustContain:  ["/28"]
        ),

        // ── Python: Folium interactive map ────────────────────────────────────
        TestCase(
            id:           "folium_map",
            name:         "Folium — interactive map",
            description:  "Map centred on GPS location with marker → HTML",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import folium
m = folium.Map(location=[user_latitude, user_longitude], zoom_start=13)
folium.Marker(
    [user_latitude, user_longitude],
    tooltip='Device Location'
).add_to(m)
result = m.get_root().render()
""",
            e2ePrompt:    nil,
            expectedKind: .html,
            gpsPreamble:  true
        ),

        // ── Python: Shapely polygon area ──────────────────────────────────────
        TestCase(
            id:          "shapely_area",
            name:        "Shapely — polygon area",
            description: "Not available on iOS",
            category:    .python,
            messages:    nil, pythonCode: nil, e2ePrompt: nil,
            isSkipped:   true,
            skipReason:  "shapely is not available on iOS"
        ),

        // ── Python: Haversine distance ────────────────────────────────────────
        TestCase(
            id:           "haversine_distance",
            name:         "Haversine — Device GPS → NYC",
            description:  "GPS distance from device coordinates to New York City",
            category:     .python,
            messages:     nil,
            pythonCode:   """
import math

def haversine(lat1, lon1, lat2, lon2):
    R = 6371
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(a))

dist = haversine(user_latitude, user_longitude, 40.7128, -74.0060)
result = f"Device → New York City: {dist:.1f} km"
""",
            e2ePrompt:    nil,
            expectedKind: .text,
            mustContain:  ["km"],
            gpsPreamble:  true
        ),

        // ── Python: GPS preamble ───────────────────────────────────────────────
        TestCase(
            id:           "gps_preamble",
            name:         "GPS — preamble injection",
            description:  "Verifies user_latitude, user_longitude, user_timezone are set",
            category:     .python,
            messages:     nil,
            pythonCode:   """
result = (
    f"lat={user_latitude:.4f}, "
    f"lon={user_longitude:.4f}, "
    f"tz=UTC{user_timezone_offset:+.1f}"
)
""",
            e2ePrompt:    nil,
            expectedKind: .text,
            mustContain:  ["lat="],
            gpsPreamble:  true
        ),

        // ── Python E2E: basic arithmetic ──────────────────────────────────────
        TestCase(
            id:           "py_e2e_math",
            name:         "Python E2E — basic arithmetic",
            description:  "\"12 × 12\" → result contains 144",
            category:     .python,
            messages:     nil,
            pythonCode:   nil,
            e2ePrompt:    "what is 12 multiplied by 12",
            expectedKind: .text,
            mustContain:  ["144"]
        ),

        // ── Python E2E: sine wave plot ─────────────────────────────────────────
        TestCase(
            id:           "py_e2e_sine_plot",
            name:         "Python E2E — sine wave plot",
            description:  "\"plot a sine wave\" → PNG image or interactive HTML",
            category:     .python,
            messages:     nil,
            pythonCode:   nil,
            e2ePrompt:    "plot a sine wave from 0 to 2 pi",
            expectedKind: .image,
            altKind:      .html
        ),

        // ── Python E2E: interactive bar chart ─────────────────────────────────
        TestCase(
            id:           "py_e2e_bar_chart",
            name:         "Python E2E — interactive bar chart",
            description:  "\"bar chart of 10,20,30,40,50\" → PNG image or interactive HTML",
            category:     .python,
            messages:     nil,
            pythonCode:   nil,
            e2ePrompt:    "show an interactive bar chart of the values 10, 20, 30, 40, 50",
            expectedKind: .image,
            altKind:      .html
        ),

        // ── Python E2E: moon phase ─────────────────────────────────────────────
        TestCase(
            id:           "py_e2e_moon_phase",
            name:         "Python E2E — moon phase",
            description:  "\"moon phase today at my location\" → text",
            category:     .python,
            messages:     nil,
            pythonCode:   nil,
            e2ePrompt:    "what is the moon phase today at my location",
            expectedKind: .text
        ),
    ]

    // ── Vision (multimodal only) ─────────────────────────────────────────────
    if isMultimodal {
        cases.append(TestCase(
            id:          "e2e_vision",
            name:        "Vision — describe test image",
            description: "4-colour 64×64 grid → non-empty description, no error",
            category:    .vision,
            messages:    [InferenceMessage(role: "user",
                                           text: "Describe this image in one sentence.")],
            pythonCode:  nil, e2ePrompt: nil,
            mustNotContain: ["[ERROR"]
        ))
    }

    return cases
}

// MARK: - TestView

struct TestView: View {

    @EnvironmentObject private var appState: AppState

    @State private var results:   [TestResult] = []
    @State private var running    = false
    @State private var currentId: String?      = nil
    @State private var runTask:   Task<Void,Never>? = nil

    private var passed:  Int { results.filter { $0.status == .passed  }.count }
    private var failed:  Int { results.filter { $0.status == .failed  }.count }
    private var skipped: Int { results.filter { $0.status == .skipped }.count }

    private func buildResults() {
        let isMulti = InferenceService.shared.isMultimodal
        let cases   = buildCases(isMultimodal: isMulti)
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
                    Button { runAll() } label: {
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
            badge("\(passed) passed",  color: .green)
            badge("\(failed) failed",  color: failed > 0 ? .red : .secondary)
            if skipped > 0 {
                badge("\(skipped) skipped", color: .orange)
            }
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

    // MARK: Run all

    private func runAll() {
        guard !running, appState.modelLoaded else { return }

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
            InferenceService.shared.resetConversation()
            await MainActor.run { running = false; currentId = nil }
        }
    }

    // MARK: Run one

    @MainActor
    private func run(_ r: TestResult) async {
        // Mark skipped tests immediately without running
        if r.testCase.isSkipped {
            r.status = .skipped
            r.detail = r.testCase.skipReason
            return
        }

        r.status = .running
        let start = Date()

        do {
            let (kind, detail) = try await execute(r.testCase)
            r.elapsed = Date().timeIntervalSince(start)
            evaluate(r, kind: kind, detail: detail)
        } catch {
            r.elapsed = Date().timeIntervalSince(start)
            r.status  = .failed
            r.detail  = "Exception: \(error.localizedDescription)"
        }
    }

    // MARK: Execute one test

    private func execute(_ tc: TestCase) async throws -> (ResultKind, String) {
        // 1. Direct model-state tests
        if !tc.isPythonDirect && !tc.isPythonE2E && !tc.isInferenceE2E {
            let detail = try executeDirect(tc)
            return (.text, detail)
        }

        // 2. Inference E2E (non-Python, no agent loop)
        if tc.isInferenceE2E {
            var messages = tc.messages!

            // Vision test: inject test image
            if tc.id == "e2e_vision" {
                guard let imageData = makeTestImageData() else {
                    throw RunError.imageGenerationFailed
                }
                messages = [InferenceMessage(role: "user",
                                             text: tc.messages!.last!.text,
                                             imageData: imageData)]
            }

            InferenceService.shared.resetConversation()
            let response = try await Task.detached(priority: .userInitiated) {
                try InferenceService.shared.chat(
                    messages: messages,
                    maxTokens: 256,
                    temperature: 0.1
                )
            }.value
            return (.text, response)
        }

        // 3. Python direct
        if tc.isPythonDirect {
            return try await executePythonDirect(tc)
        }

        // 4. Python E2E (agent loop)
        if tc.isPythonE2E {
            return try await executePythonE2E(tc)
        }

        throw RunError.unknownDirectTest(tc.id)
    }

    // MARK: Direct model-state

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

    // MARK: Python direct

    private func executePythonDirect(_ tc: TestCase) async throws -> (ResultKind, String) {
        guard let code = tc.pythonCode else {
            throw RunError.unknownDirectTest(tc.id)
        }

        // Build GPS preamble if needed
        var fullCode = code
        if tc.gpsPreamble {
            let preamble = await buildGPSPreamble()
            fullCode = preamble + "\n" + code
        }

        let result = await PythonRunner.execute(code: fullCode)
        return toolResultToKindAndDetail(result)
    }

    // MARK: Python E2E (agent loop)

    private func executePythonE2E(_ tc: TestCase) async throws -> (ResultKind, String) {
        guard let prompt = tc.e2ePrompt else {
            throw RunError.unknownDirectTest(tc.id)
        }
        guard appState.modelLoaded else {
            return (.text, "Skipped — no model loaded")
        }

        let sysBlock = ToolRegistry.shared.buildSystemPromptBlock()
        var messages: [InferenceMessage] = []
        if !sysBlock.isEmpty {
            messages.append(InferenceMessage(role: "system", text: sysBlock))
        }
        messages.append(InferenceMessage(role: "user", text: prompt))

        var lastToolResult: ToolResult? = nil
        var finalText = ""

        // Max 3 agent iterations
        for _ in 0..<3 {
            InferenceService.shared.resetConversation()
            let response = try await Task.detached(priority: .userInitiated) {
                try InferenceService.shared.chat(
                    messages: messages,
                    maxTokens: 768,
                    temperature: 0.1
                )
            }.value

            if AgentLoop.hasToolCall(response) {
                guard let toolCall = AgentLoop.parse(response) else {
                    finalText = response
                    break
                }
                if let tool = ToolRegistry.shared.find(toolCall.toolName) {
                    let toolResult = await tool.execute(toolCall.args)
                    lastToolResult = toolResult
                    let resultText = toolResult.modelText
                    messages.append(InferenceMessage(role: "assistant", text: response))
                    messages.append(AgentLoop.toolResultMessage(
                        toolName: toolCall.toolName, result: resultText))
                } else {
                    finalText = response
                    break
                }
            } else {
                finalText = response
                break
            }
        }

        // Evaluate from last tool result or final text
        if let tr = lastToolResult {
            return toolResultToKindAndDetail(tr)
        }
        return (.text, finalText)
    }

    // MARK: Shared helpers

    /// Fetches device GPS and returns Python variable declarations as a string.
    private func buildGPSPreamble() async -> String {
        if let loc = try? await LocationService.shared.requestLocation() {
            return loc.pythonPreamble
        }
        // Fallback: Swisher, IA (41.8450°N, 91.7026°W, UTC-5)
        return """
user_latitude = 41.845000
user_longitude = -91.702600
user_timezone_offset = -5.0
import datetime as _dt
user_timezone = _dt.timezone(_dt.timedelta(hours=-5.0))

"""
    }

    /// Converts a ToolResult to (ResultKind, content string) for evaluation.
    private func toolResultToKindAndDetail(_ result: ToolResult) -> (ResultKind, String) {
        switch result {
        case .image(_, let caption):
            return (.image, caption)
        case .text(let s):
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("<!DOCTYPE") ||
               trimmed.lowercased().hasPrefix("<html") {
                return (.html, s)
            }
            return (.text, s)
        }
    }

    // MARK: Evaluate

    private func evaluate(_ r: TestResult, kind: ResultKind, detail: String) {
        let tc = r.testCase

        // Error markers in detail
        if detail.hasPrefix("{\"error\"") ||
           detail.contains("Traceback (most recent call last)") ||
           detail.hasPrefix("Error:") {
            r.status = .failed
            r.detail = detail.prefix(400).description
            return
        }

        // Check result kind for Python tests
        if tc.isPythonDirect || tc.isPythonE2E {
            if !tc.accepts(kind) {
                let expected: String
                if let alt = tc.altKind {
                    expected = "\(tc.expectedKind) or \(alt)"
                } else {
                    expected = "\(tc.expectedKind)"
                }
                r.status = .failed
                r.detail = "Expected \(expected), got \(kind).\n\(detail.prefix(200))"
                return
            }
        }

        // mustContain checks (case-insensitive)
        let lower = detail.lowercased()
        for kw in tc.mustContain {
            if !lower.contains(kw.lowercased()) {
                r.status = .failed
                r.detail = "Expected \"\(kw)\" not found in:\n\(detail)"
                return
            }
        }

        // mustNotContain checks
        for kw in tc.mustNotContain {
            if lower.contains(kw.lowercased()) {
                r.status = .failed
                r.detail = "Unexpected \"\(kw)\" found in:\n\(detail)"
                return
            }
        }

        // Non-empty check for E2E tests
        if (tc.isInferenceE2E || tc.isPythonE2E) &&
           detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.status = .failed
            r.detail = "Model returned an empty response."
            return
        }

        r.status = .passed
        r.detail = detail.count > 300 ? "\(detail.prefix(300))…" : detail
    }

    // MARK: Test image (4-colour 64×64 grid)

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
        case .modelNotLoaded:           return "Model is not loaded."
        case .noModelId:                return "No model ID found."
        case .imageGenerationFailed:    return "Could not generate test image."
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
                        if result.testCase.isInferenceE2E || result.testCase.isPythonE2E {
                            e2eChip
                        }
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
        case .skipped: return "minus.circle"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .pending: return .secondary
        case .running: return .accentColor
        case .passed:  return .green
        case .failed:  return .red
        case .skipped: return .orange
        }
    }

    private var categoryChip: some View {
        let (label, color): (String, Color) = switch result.testCase.category {
        case .model:     ("Model",     .blue)
        case .inference: ("Inference", .purple)
        case .vision:    ("Vision",    .teal)
        case .python:    ("Python",    .green)
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
