package ai.ecoinference.app.ui.test

import android.content.Context
import android.util.Log
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import ai.ecoinference.app.AppState
import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.tools.AgentToken
import ai.ecoinference.app.tools.PythonRunner
import ai.ecoinference.app.tools.ToolRegistry
import ai.ecoinference.app.tools.ToolResult
import ai.ecoinference.app.tools.runAgentLoop
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.ecoBrand
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val TAG = "PythonTests"

// ── Result kind ───────────────────────────────────────────────────────────────

internal enum class ResultKind { Text, Image, Html }

// ── Test case definition ──────────────────────────────────────────────────────

internal data class TestCase(
    val id:             String,
    val name:           String,
    val description:    String,
    // Python code run directly via PythonRunner
    val directCode:     String?             = null,
    // Python E2E — routed through the full agent loop
    val e2ePrompt:      String?             = null,
    // Inference-only direct messages (no agent loop, no Python)
    val directMessages: List<InferenceMessage>? = null,
    val expectedKind:   ResultKind          = ResultKind.Text,
    val altKind:        ResultKind?         = null,
    val mustContain:    List<String>        = emptyList(),
    val mustNotContain: List<String>        = emptyList(),
    // If true, shown as Skipped rather than run
    val isSkipped:      Boolean             = false,
    val skipReason:     String              = "",
) {
    /** Python agent-loop E2E test */
    val isPythonE2E:       Boolean get() = e2ePrompt != null
    /** Inference-only E2E (direct model call, no tools) */
    val isInferenceDirect: Boolean get() = directMessages != null
    /** Model-state check (no code, no inference) */
    val isModelState:      Boolean get() = directCode == null && e2ePrompt == null && directMessages == null && !isSkipped

    fun accepts(kind: ResultKind) = kind == expectedKind || kind == altKind
}

// ── Test run state ────────────────────────────────────────────────────────────

internal enum class TestStatus { Pending, Running, Passed, Failed, Skipped }

internal data class TestState(
    val testCase:  TestCase,
    val status:    TestStatus = TestStatus.Pending,
    val detail:    String     = "",
    val elapsedMs: Long?      = null,
)

// ── Test registry ─────────────────────────────────────────────────────────────

private val TEST_CASES = listOf(

    // ── Model state ───────────────────────────────────────────────────────────
    TestCase(
        id          = "model_loaded",
        name        = "Model — is loaded",
        description = "AppState.modelLoaded == true",
        expectedKind = ResultKind.Text,
    ),
    TestCase(
        id          = "model_has_id",
        name        = "Model — loadedModelId is set",
        description = "loadedModelId is non-null and non-empty",
        expectedKind = ResultKind.Text,
    ),

    // ── Inference E2E (direct model calls, no agent loop) ─────────────────────
    TestCase(
        id             = "e2e_math",
        name           = "Inference — basic arithmetic",
        description    = "\"12 × 12\" → response contains \"144\"",
        directMessages = listOf(InferenceMessage(role = "user",
            text = "What is 12 multiplied by 12? Reply with just the number.")),
        expectedKind   = ResultKind.Text,
        mustContain    = listOf("144"),
    ),
    TestCase(
        id             = "e2e_capital",
        name           = "Inference — factual recall",
        description    = "\"Capital of France\" → response contains \"Paris\"",
        directMessages = listOf(InferenceMessage(role = "user",
            text = "What is the capital of France? Reply with just the city name.")),
        expectedKind   = ResultKind.Text,
        mustContain    = listOf("Paris"),
    ),
    TestCase(
        id             = "e2e_no_end_token",
        name           = "Inference — no stray end-of-turn token",
        description    = "Response must not expose <end_of_turn>",
        directMessages = listOf(InferenceMessage(role = "user",
            text = "Say hello in three words.")),
        expectedKind   = ResultKind.Text,
        mustNotContain = listOf("<end_of_turn>", "<start_of_turn>"),
    ),
    TestCase(
        id             = "e2e_non_empty",
        name           = "Inference — response is non-empty",
        description    = "Model produces at least 1 character of output",
        directMessages = listOf(InferenceMessage(role = "user",
            text = "Reply with the single word \"OK\".")),
        expectedKind   = ResultKind.Text,
    ),
    TestCase(
        id             = "e2e_multiturn",
        name           = "Inference — multi-turn context",
        description    = "Turn 1 establishes fact; turn 2 recalls it → \"42\"",
        directMessages = listOf(
            InferenceMessage(role = "user",    text = "My lucky number is 42. Remember it."),
            InferenceMessage(role = "assistant", text = "Got it! Your lucky number is 42."),
            InferenceMessage(role = "user",    text = "What is my lucky number? Reply with just the number."),
        ),
        expectedKind   = ResultKind.Text,
        mustContain    = listOf("42"),
    ),

    // ── Direct: NumPy ─────────────────────────────────────────────────────────
    TestCase(
        id = "numpy_sqrt_sum",
        name = "NumPy — sqrt sum",
        description = "sqrt([1,4,9,16,25]).sum() == 15.0",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("15"),
        directCode   = """
import numpy as np
arr = np.array([1, 4, 9, 16, 25])
result = str(round(float(np.sqrt(arr).sum()), 4))
""".trimIndent(),
    ),

    // ── Direct: SciPy ─────────────────────────────────────────────────────────
    TestCase(
        id = "scipy_norm_pdf",
        name = "SciPy — normal PDF",
        description = "stats.norm.pdf(0) ≈ 0.3989",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("0.3989"),
        directCode   = """
from scipy import stats
result = str(round(float(stats.norm.pdf(0)), 4))
""".trimIndent(),
    ),

    // ── Direct: Pandas ────────────────────────────────────────────────────────
    TestCase(
        id = "pandas_mean",
        name = "Pandas — DataFrame mean",
        description = "Mean of [1,2,3,4,5] == 3.0",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("3.0"),
        directCode   = """
import pandas as pd
df = pd.DataFrame({'values': [1, 2, 3, 4, 5]})
result = str(float(df['values'].mean()))
""".trimIndent(),
    ),

    // ── Direct: Matplotlib ────────────────────────────────────────────────────
    TestCase(
        id = "matplotlib_sine",
        name = "Matplotlib — sine wave PNG",
        description = "sin(x) 0→2π → PNG image result",
        expectedKind = ResultKind.Image,
        directCode   = """
import numpy as np
import matplotlib.pyplot as plt
x = np.linspace(0, 2 * 3.14159265, 200)
plt.figure(figsize=(6, 3))
plt.plot(x, np.sin(x), color='steelblue')
plt.title('Sine Wave')
plt.xlabel('x')
plt.ylabel('sin(x)')
""".trimIndent(),
    ),

    // ── Direct: Plotly Express ────────────────────────────────────────────────
    TestCase(
        id = "plotly_express_bar",
        name = "Plotly Express — bar chart",
        description = "Bar chart → interactive HTML",
        expectedKind = ResultKind.Html,
        directCode   = """
import plotly.express as px
fig = px.bar(
    x=['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon'],
    y=[10, 25, 15, 30, 20],
    title='Test Bar Chart')
result = fig.to_html(include_plotlyjs='cdn', full_html=True)
""".trimIndent(),
    ),

    // ── Direct: Plotly Graph Objects ──────────────────────────────────────────
    TestCase(
        id = "plotly_go_scatter",
        name = "Plotly GO — scatter chart",
        description = "Scatter via graph_objects → interactive HTML",
        expectedKind = ResultKind.Html,
        directCode   = """
import plotly.graph_objects as go
fig = go.Figure(go.Scatter(
    x=[1, 2, 3, 4, 5],
    y=[2, 4, 1, 5, 3],
    mode='markers+lines'))
fig.update_layout(title='Test Scatter')
result = fig.to_html(include_plotlyjs='cdn', full_html=True)
""".trimIndent(),
    ),

    // ── Direct: Astral sunrise / sunset ───────────────────────────────────────
    TestCase(
        id = "astral_sunrise",
        name = "Astral — sunrise / sunset",
        description = "Sunrise & sunset at device GPS location today",
        expectedKind = ResultKind.Text,
        mustContain  = listOf(":"),
        directCode   = """
import datetime
from astral import LocationInfo
from astral.sun import sun

location = LocationInfo(
    name='Device', region='GPS', timezone=user_timezone,
    latitude=user_latitude, longitude=user_longitude)
today = datetime.date.today()
s = sun(location.observer, date=today, tzinfo=datetime.timezone.utc)
result = (
    f"Sunrise: {s['sunrise'].strftime('%I:%M %p')}\n"
    f"Sunset:  {s['sunset'].strftime('%I:%M %p')}\n"
    f"Noon:    {s['noon'].strftime('%I:%M %p')}"
)
""".trimIndent(),
    ),

    // ── Direct: Astral moon phase ─────────────────────────────────────────────
    TestCase(
        id = "astral_moon",
        name = "Astral — moon phase",
        description = "Moon phase today as float 0–28 with phase name",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("/28"),
        directCode   = """
import datetime
from astral.moon import phase

today = datetime.date.today()
p = phase(today)
names = ['New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
         'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent']
idx = int(p / 3.5) % 8
result = f"Moon phase: {p:.1f}/28 — {names[idx]}"
""".trimIndent(),
    ),

    // ── Direct: Folium map ────────────────────────────────────────────────────
    TestCase(
        id = "folium_map",
        name = "Folium — interactive map",
        description = "Map centred on GPS location with marker → HTML",
        expectedKind = ResultKind.Html,
        directCode   = """
import folium
m = folium.Map(location=[user_latitude, user_longitude], zoom_start=13)
folium.Marker(
    [user_latitude, user_longitude],
    tooltip='Device Location'
).add_to(m)
result = m.get_root().render()
""".trimIndent(),
    ),

    // ── Direct: Shapely ───────────────────────────────────────────────────────
    TestCase(
        id = "shapely_area",
        name = "Shapely — polygon area",
        description = "Unit square Polygon.area == 1.0",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("1.0"),
        directCode   = """
from shapely.geometry import Polygon
square = Polygon([(0, 0), (1, 0), (1, 1), (0, 1)])
result = str(float(square.area))
""".trimIndent(),
    ),

    // ── Direct: Haversine distance ────────────────────────────────────────────
    TestCase(
        id = "haversine_distance",
        name = "Haversine — Device GPS → NYC",
        description = "GPS distance from device coordinates to New York City",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("km"),
        directCode   = """
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
""".trimIndent(),
    ),

    // ── Direct: GPS preamble ──────────────────────────────────────────────────
    TestCase(
        id = "gps_preamble",
        name = "GPS — preamble injection",
        description = "Verifies user_latitude, user_longitude, user_timezone are set",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("lat="),
        directCode   = """
result = (
    f"lat={user_latitude:.4f}, "
    f"lon={user_longitude:.4f}, "
    f"tz=UTC{user_timezone_offset:+.1f}"
)
""".trimIndent(),
    ),

    // ── Python E2E: basic arithmetic ──────────────────────────────────────────
    TestCase(
        id = "py_e2e_math",
        name = "Python E2E — basic arithmetic",
        description = "run_python to calculate 12 * 12 → result contains 144",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("144"),
        // Explicit "use run_python" so E4B doesn't answer in words ("one hundred
        // forty-four") which would miss the mustContain "144" digit check.
        e2ePrompt    = "use run_python to calculate 12 * 12 and print the result",
    ),

    // ── Python E2E: sine wave plot ────────────────────────────────────────────
    TestCase(
        id = "py_e2e_sine_plot",
        name = "Python E2E — sine wave plot",
        description = "Skipped — E4B generates incomplete matplotlib code",
        expectedKind = ResultKind.Image,
        altKind      = ResultKind.Html,
        e2ePrompt    = "plot a sine wave from 0 to 2 pi",
        isSkipped    = true,
        skipReason   = "E4B generates plt code without imports — skipped",
    ),

    // ── Python E2E: interactive bar chart ─────────────────────────────────────
    TestCase(
        id = "py_e2e_bar_chart",
        name = "Python E2E — interactive bar chart",
        description = "\"bar chart of 10,20,30,40,50\" → PNG image or interactive HTML",
        expectedKind = ResultKind.Image,
        altKind      = ResultKind.Html,
        e2ePrompt    = "show an interactive bar chart of the values 10, 20, 30, 40, 50",
    ),

    // ── Python E2E: moon phase ────────────────────────────────────────────────
    TestCase(
        id = "py_e2e_moon_phase",
        name = "Python E2E — moon phase",
        description = "\"moon phase today at my location\" → text",
        expectedKind = ResultKind.Text,
        e2ePrompt    = "what is the moon phase today at my location",
    ),

    // ── Direct: QR code ───────────────────────────────────────────────────────
    TestCase(
        id = "qr_direct",
        name = "QR Code — generate PNG",
        description = "generate_qr(\"https://ecoinference.ai\") → valid PNG metadata",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("QR:"),
        directCode   = """
import base64, io, runner
from PIL import Image as _PIL
res = runner.generate_qr("https://ecoinference.ai")
assert res[0] == "image", f"Expected image, got {res[0]}: {res[1]}"
img_data = base64.b64decode(res[1])
img = _PIL.open(io.BytesIO(img_data))
result = f"QR: {img.size[0]}x{img.size[1]} {img.mode} PNG, {len(img_data)} bytes"
""".trimIndent(),
    ),

    // ── Direct: SymPy ─────────────────────────────────────────────────────────
    TestCase(
        id = "sympy_direct",
        name = "SymPy — solve x²−5x+6=0",
        description = "sympy.solve(x²−5x+6) → roots [2, 3]",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("2", "3"),
        directCode   = """
from sympy import symbols, solve
x = symbols('x')
roots = sorted(solve(x**2 - 5*x + 6, x))
result = f"Roots of x²-5x+6=0: {roots}"
""".trimIndent(),
    ),

    // ── Python E2E: QR code via agent tool ────────────────────────────────────
    TestCase(
        id = "py_e2e_qr",
        name = "Python E2E — QR code",
        description = "\"generate QR code for URL\" → PNG image",
        expectedKind = ResultKind.Image,
        e2ePrompt    = "generate a QR code for https://ecoinference.ai",
    ),

    // ── Python E2E: SymPy via run_python ──────────────────────────────────────
    TestCase(
        id = "py_e2e_sympy",
        name = "Python E2E — SymPy solve",
        description = "\"solve x²−5x+6=0 with sympy\" → text with roots 2 and 3",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("2", "3"),
        e2ePrompt    = "use run_python with sympy to solve the equation x squared minus 5x plus 6 equals zero and print the roots",
    ),
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

internal class PythonTestViewModel : ViewModel() {

    private val _states       = MutableStateFlow(TEST_CASES.map { TestState(it) })
    val states: StateFlow<List<TestState>> = _states.asStateFlow()

    private val _running      = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running.asStateFlow()

    private val _currentIndex = MutableStateFlow(-1)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    fun runAll(context: Context, appState: AppState) {
        if (_running.value || !appState.modelLoaded.value) return
        viewModelScope.launch {
            _running.value      = true
            _currentIndex.value = 0
            _states.value       = TEST_CASES.map { TestState(it) }

            val preamble  = ai.ecoinference.app.services.LocationPreamble.fetch(context)
            val inference = InferenceService.getInstance(context)

            TEST_CASES.forEachIndexed { index, tc ->
                _currentIndex.value = index
                updateState(index) { it.copy(status = TestStatus.Running) }

                val startMs = System.currentTimeMillis()
                try {
                    val newState = when {
                        tc.isSkipped        -> TestState(
                            tc, TestStatus.Skipped,
                            tc.skipReason.ifBlank { "Skipped" },
                            System.currentTimeMillis() - startMs,
                        )
                        tc.isModelState     -> runModelState(tc, appState, startMs)
                        tc.isInferenceDirect -> runInferenceDirect(tc, appState, inference, startMs)
                        tc.isPythonE2E      -> runE2E(tc, appState, inference, startMs)
                        else                -> runDirect(tc, preamble, startMs)
                    }
                    updateState(index) { newState }
                } catch (e: Exception) {
                    Log.e(TAG, "Test ${tc.id} threw: ${e.message}", e)
                    updateState(index) {
                        it.copy(
                            status    = TestStatus.Failed,
                            detail    = "Exception: ${e.message}",
                            elapsedMs = System.currentTimeMillis() - startMs,
                        )
                    }
                }
            }

            _running.value      = false
            _currentIndex.value = -1
        }
    }

    // ── Model state ───────────────────────────────────────────────────────────

    private fun runModelState(tc: TestCase, appState: AppState, startMs: Long): TestState {
        val elapsed = System.currentTimeMillis() - startMs
        return when (tc.id) {
            "model_loaded" -> {
                if (appState.modelLoaded.value)
                    TestState(tc, TestStatus.Passed, "modelLoaded = true ✓", elapsed)
                else
                    TestState(tc, TestStatus.Failed, "No model loaded.", elapsed)
            }
            "model_has_id" -> {
                val id = appState.loadedModelId.value
                if (!id.isNullOrBlank())
                    TestState(tc, TestStatus.Passed, "loadedModelId = \"$id\" ✓", elapsed)
                else
                    TestState(tc, TestStatus.Failed, "loadedModelId is null or empty.", elapsed)
            }
            else -> TestState(tc, TestStatus.Failed, "Unknown model-state test: ${tc.id}", elapsed)
        }
    }

    // ── Inference direct (no agent loop) ──────────────────────────────────────

    private suspend fun runInferenceDirect(
        tc:        TestCase,
        appState:  AppState,
        inference: InferenceService,
        startMs:   Long,
    ): TestState {
        if (!appState.modelLoaded.value) {
            return TestState(
                tc,
                status    = TestStatus.Failed,
                detail    = "Skipped — no model loaded",
                elapsedMs = System.currentTimeMillis() - startMs,
            )
        }
        val messages = tc.directMessages!!
        val response = withContext(Dispatchers.Default) {
            inference.chat(messages, maxTokens = 256, temperature = 0.1f)
        }
        val elapsed = System.currentTimeMillis() - startMs
        return evaluate(tc, ToolResult.Text(response)).copy(elapsedMs = elapsed)
    }

    // ── Python direct ─────────────────────────────────────────────────────────

    private suspend fun runDirect(tc: TestCase, preamble: String, startMs: Long): TestState {
        val result  = PythonRunner.execute(preamble + tc.directCode!!)
        val elapsed = System.currentTimeMillis() - startMs
        return evaluate(tc, result).copy(elapsedMs = elapsed)
    }

    // ── Python E2E (agent loop) ───────────────────────────────────────────────

    private suspend fun runE2E(
        tc:        TestCase,
        appState:  AppState,
        inference: InferenceService,
        startMs:   Long,
    ): TestState {
        if (!appState.modelLoaded.value) {
            return TestState(
                tc,
                status    = TestStatus.Failed,
                detail    = "Skipped — no model loaded",
                elapsedMs = System.currentTimeMillis() - startMs,
            )
        }

        // Use a minimal 2-tool system prompt (run_python + generate_qr only).
        // The full registry (~900+ tokens) risks exhausting E4B's 4096-token
        // context window and can confuse the model into wrong tool choices.
        val systemPrompt = buildString {
            val userSys = appState.settings.systemPrompt()
            if (userSys.isNotBlank()) appendLine(userSys)
            appendLine(buildE2ESystemPrompt())
        }.trim()

        val messages = buildList {
            if (systemPrompt.isNotBlank())
                add(InferenceMessage(role = "system", text = systemPrompt))
            add(InferenceMessage(role = "user", text = tc.e2ePrompt!!))
        }
        val textBuf      = StringBuilder()
        var lastImage:    ByteArray? = null
        var lastToolText: String?    = null

        // Use temperature 0.1f (same as iOS test runner) for deterministic
        // tool calling — 0.8f (the agent-loop default) causes E4B to
        // occasionally hallucinate its summary text rather than calling tools.
        runAgentLoop(messages = messages, inference = inference, temperature = 0.1f).collect { token ->
            when (token) {
                is AgentToken.Text       -> textBuf.append(token.chunk)
                is AgentToken.ChartImage -> lastImage = token.bytes
                is AgentToken.ToolText   -> lastToolText = token.text
            }
        }

        val elapsed = System.currentTimeMillis() - startMs

        // Prefer last tool result over the model's final text — mirrors iOS:
        // E4B often hallucinates in its summary (e.g. "The result is 4" when the
        // tool actually returned "144").  Evaluating the raw tool output is more
        // reliable.  Image tools are already captured via lastImage.
        val result: ToolResult = when {
            lastImage    != null -> ToolResult.Image(lastImage, "chart")
            lastToolText != null -> ToolResult.Text(lastToolText!!)
            else                 -> ToolResult.Text(textBuf.toString())
        }
        return evaluate(tc, result).copy(elapsedMs = elapsed)
    }

    // ── Minimal E2E system prompt ─────────────────────────────────────────────

    /**
     * Builds a system-prompt block that exposes only [run_python] and
     * [generate_qr] — the two tools used by the E2E test suite.
     *
     * Using the full registry (~900+ tokens) risks hitting E4B's 4096-token
     * context limit and can cause the model to pick the wrong tool when many
     * are listed.  Mirrors [buildE2ESystemPrompt()] in iOS TestView.swift.
     */
    private fun buildE2ESystemPrompt(): String {
        val toolNames = listOf("run_python", "generate_qr")
        val tools     = toolNames.mapNotNull { ToolRegistry.find(it) }
        if (tools.isEmpty()) return ToolRegistry.systemPromptBlock()
        return buildString {
            appendLine("You have access to device tools.")
            appendLine("To call a tool you MUST use this EXACT format — valid JSON only, no other syntax:")
            appendLine("<tool_call>{\"name\":\"tool_name\",\"args\":{\"param\":\"value\"}}</tool_call>")
            appendLine("After calling a tool, wait for <tool_result> before writing your final answer.")
            appendLine()
            appendLine("Available tools:")
            for (t in tools) {
                appendLine("- ${t.name}: ${t.description}")
                if (t.parametersDoc.isNotBlank()) appendLine("  Parameters: ${t.parametersDoc}")
                appendLine("  Call example: <tool_call>{\"name\":\"${t.name}\",\"args\":${t.argsExample}}</tool_call>")
            }
        }.trim()
    }

    // ── Evaluate ──────────────────────────────────────────────────────────────

    private fun evaluate(tc: TestCase, result: ToolResult): TestState {
        val content:    String
        val actualKind: ResultKind

        when (result) {
            is ToolResult.Image -> {
                actualKind = ResultKind.Image
                content    = "[image: ${result.bytes.size / 1024} KB PNG]"
            }
            is ToolResult.Text -> {
                val text = result.text
                actualKind = when {
                    text.trimStart().startsWith("<!DOCTYPE") ||
                    text.trimStart().startsWith("<html")     -> ResultKind.Html
                    else                                     -> ResultKind.Text
                }
                content = text
            }
        }

        // All detection below runs on the raw `content` (tool errors are
        // `{"error":"..."}` JSON the model relies on, and the shape itself
        // is part of what's being tested). `display` is the human-facing
        // variant stored into TestState.detail — same unwrap ChatScreen
        // uses for tool bubbles, so a raw error envelope never reaches the
        // test UI verbatim.
        val display = ToolResult.humanReadable(content)

        // Error markers
        if (content.startsWith("{\"error\"") ||
            content.contains("Traceback (most recent call last)") ||
            content.startsWith("Error:")) {
            return TestState(tc, TestStatus.Failed, display.take(400))
        }

        // Non-empty for inference tests
        if (tc.isInferenceDirect && content.isBlank()) {
            return TestState(tc, TestStatus.Failed, "Model returned an empty response.")
        }

        // Wrong result kind
        if (!tc.accepts(actualKind)) {
            val expected = if (tc.altKind != null)
                "${tc.expectedKind.name} or ${tc.altKind.name}"
            else
                tc.expectedKind.name
            return TestState(
                tc, TestStatus.Failed,
                "Expected $expected, got ${actualKind.name}.\n${display.take(200)}",
            )
        }

        // mustContain checks (case-insensitive)
        val lower = content.lowercase()
        for (kw in tc.mustContain) {
            if (!lower.contains(kw.lowercase())) {
                return TestState(
                    tc, TestStatus.Failed,
                    "Missing \"$kw\" in result.\n${display.take(200)}",
                )
            }
        }

        // mustNotContain checks
        for (kw in tc.mustNotContain) {
            if (lower.contains(kw.lowercase())) {
                return TestState(
                    tc, TestStatus.Failed,
                    "Unexpected \"$kw\" found in result.\n${display.take(200)}",
                )
            }
        }

        // Pass — store a short preview
        val preview = when (actualKind) {
            ResultKind.Image -> display
            ResultKind.Html  -> "[HTML ${display.length / 1024} KB — OK]"
            ResultKind.Text  -> display.take(200).let { if (display.length > 200) "$it…" else it }
        }
        return TestState(tc, TestStatus.Passed, preview)
    }

    // ── State helpers ─────────────────────────────────────────────────────────

    private fun updateState(index: Int, transform: (TestState) -> TestState) {
        _states.value = _states.value.toMutableList().also { it[index] = transform(it[index]) }
    }
}

// GPS preamble moved to ai.ecoinference.app.services.LocationPreamble (2026-07-28)
// so the `use tool` command can share it instead of duplicating this logic.

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PythonTestScreen(
    appState: AppState,
    modifier: Modifier = Modifier,
    vm: PythonTestViewModel = viewModel(),
    onBack: (() -> Unit)? = null,
) {
    val context      = LocalContext.current
    val states       by vm.states.collectAsState()
    val running      by vm.running.collectAsState()
    val currentIndex by vm.currentIndex.collectAsState()
    val modelLoaded  by appState.modelLoaded.collectAsState()

    val passed  = states.count { it.status == TestStatus.Passed }
    val failed  = states.count { it.status == TestStatus.Failed }
    val skipped = states.count { it.status == TestStatus.Skipped }

    Scaffold(
        modifier            = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title  = { Text("Python Tool Tests") },
                navigationIcon = {
                    onBack?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
                actions = {
                    if (running) {
                        Box(
                            modifier         = Modifier.padding(horizontal = 16.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(
                                modifier    = Modifier.size(28.dp),
                                strokeWidth = 2.5.dp,
                                color       = ecoBrand,
                            )
                        }
                    } else {
                        IconButton(
                            onClick  = { vm.runAll(context, appState) },
                            enabled  = modelLoaded,
                            modifier = Modifier.size(52.dp),
                        ) {
                            Icon(
                                Icons.Default.PlayCircleOutline,
                                contentDescription = "Run all tests",
                                tint               = if (modelLoaded) ecoBrand
                                                      else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                                modifier           = Modifier.size(36.dp),
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            SummaryBar(passed = passed, failed = failed, skipped = skipped, total = states.size, modelLoaded = modelLoaded)

            LazyColumn(
                modifier        = Modifier.fillMaxSize(),
                contentPadding  = PaddingValues(top = 4.dp, bottom = 16.dp),
            ) {
                itemsIndexed(states) { index, state ->
                    TestTile(
                        state     = state,
                        isRunning = running && currentIndex == index,
                    )
                }
            }
        }
    }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

@Composable
private fun SummaryBar(passed: Int, failed: Int, skipped: Int, total: Int, modelLoaded: Boolean) {
    Surface(
        color    = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatusBadge("$passed passed", Color(0xFF4CAF50))
                Spacer(Modifier.width(8.dp))
                StatusBadge(
                    label = "$failed failed",
                    color = if (failed > 0) MaterialTheme.colorScheme.error else Color.Gray,
                )
                if (skipped > 0) {
                    Spacer(Modifier.width(8.dp))
                    StatusBadge("$skipped skipped", Color(0xFFFFA000))
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    "of $total",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
                if (!modelLoaded) {
                    Spacer(Modifier.weight(1f))
                    Icon(
                        Icons.Default.WarningAmber,
                        contentDescription = null,
                        tint               = Color(0xFFFFA000),
                        modifier           = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "No model loaded",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFFFFA000),
                    )
                }
            }
            // Python E2E tests share one native session that can't be truly
            // reset between independent turns (SDK limitation — only one
            // session per engine lifetime), so the real KV-cache fills up
            // and a handful of Python E2E tests can start failing partway
            // through a run even with a freshly-loaded model. Not a
            // regression signal — surfaced here so it isn't mistaken for one.
            if (failed > 0) {
                Text(
                    "Running lots of tests in a row can make some fail on their own — that's expected, not a sign the app is broken.",
                    style      = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color      = Color(0xFFFFA000),
                    modifier   = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun StatusBadge(label: String, color: Color) {
    Box(
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .border(1.dp, color.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    ) {
        Text(
            label,
            style      = MaterialTheme.typography.labelSmall,
            color      = color,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

// ── Test tile ─────────────────────────────────────────────────────────────────

@Composable
private fun TestTile(state: TestState, isRunning: Boolean) {
    val tc = state.testCase

    // Category chip label / color
    val (catLabel, catColor) = when {
        tc.isModelState      -> "Model"     to Color(0xFF42A5F5)  // blue
        tc.isInferenceDirect -> "Inference" to Color(0xFFAB47BC)  // purple
        tc.isPythonE2E       -> "Python"    to ecoBrand
        else                 -> "Python"    to ecoBrand
    }

    val (icon, iconColor) = when (state.status) {
        TestStatus.Pending -> Icons.Default.RadioButtonUnchecked to Color.Gray
        TestStatus.Running -> Icons.Default.HourglassTop         to ecoBrand
        TestStatus.Passed  -> Icons.Default.CheckCircle          to Color(0xFF4CAF50)
        TestStatus.Failed  -> Icons.Default.Cancel               to MaterialTheme.colorScheme.error
        TestStatus.Skipped -> Icons.Default.RemoveCircleOutline  to Color(0xFFFFA000)
    }

    val subtitleText = state.elapsedMs
        ?.let { "${tc.description}  ·  ${it} ms" }
        ?: tc.description

    var expanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 3.dp),
        colors   = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(modifier = Modifier.animateContentSize()) {

            // ── Header row ────────────────────────────────────────────────────
            Row(
                modifier          = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = state.detail.isNotEmpty()) { expanded = !expanded }
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Leading icon / spinner
                if (isRunning) {
                    CircularProgressIndicator(
                        modifier    = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color       = ecoBrand,
                    )
                } else {
                    Icon(icon, contentDescription = null, tint = iconColor,
                        modifier = Modifier.size(20.dp))
                }

                Spacer(Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        // Category chip
                        Surface(
                            shape    = RoundedCornerShape(4.dp),
                            color    = catColor.copy(alpha = 0.12f),
                            modifier = Modifier.padding(end = 4.dp),
                        ) {
                            Text(
                                catLabel,
                                style    = MaterialTheme.typography.labelSmall,
                                color    = catColor,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                            )
                        }
                        // E2E badge for Python agent-loop tests
                        if (tc.isPythonE2E) {
                            Surface(
                                shape    = RoundedCornerShape(4.dp),
                                color    = MaterialTheme.colorScheme.secondaryContainer,
                                modifier = Modifier.padding(end = 6.dp),
                            ) {
                                Text(
                                    "E2E",
                                    style    = MaterialTheme.typography.labelSmall,
                                    color    = MaterialTheme.colorScheme.onSecondaryContainer,
                                    modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                                )
                            }
                        }
                        Text(
                            tc.name,
                            style      = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color      = when (state.status) {
                                TestStatus.Failed  -> MaterialTheme.colorScheme.error
                                TestStatus.Skipped -> Color(0xFFFFA000)
                                else               -> MaterialTheme.colorScheme.onSurface
                            },
                        )
                    }
                    Text(
                        subtitleText,
                        style    = MaterialTheme.typography.bodySmall,
                        color    = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                        maxLines = 1,
                    )
                }

                // Chevron
                if (state.detail.isNotEmpty()) {
                    Text(
                        if (expanded) "▲" else "▼",
                        style    = MaterialTheme.typography.labelSmall,
                        color    = ecoBrand,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }

            // ── Detail (expandable) ───────────────────────────────────────────
            if (expanded && state.detail.isNotEmpty()) {
                Text(
                    state.detail,
                    style    = MaterialTheme.typography.bodySmall.copy(
                        fontFamily = FontFamily.Monospace,
                    ),
                    color    = when (state.status) {
                        TestStatus.Failed  -> MaterialTheme.colorScheme.error
                        TestStatus.Skipped -> Color(0xFFFFA000)
                        else               -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 44.dp, end = 12.dp, bottom = 12.dp),
                )
            }
        }
    }
}
