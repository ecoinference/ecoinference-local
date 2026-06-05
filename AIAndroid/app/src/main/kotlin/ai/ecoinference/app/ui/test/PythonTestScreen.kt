package ai.ecoinference.app.ui.test

import android.annotation.SuppressLint
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
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.RemoveCircleOutline
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
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.Tasks
import ai.ecoinference.app.AppState
import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.tools.AgentToken
import ai.ecoinference.app.tools.PythonRunner
import ai.ecoinference.app.tools.ToolRegistry
import ai.ecoinference.app.tools.ToolResult
import ai.ecoinference.app.tools.runAgentLoop
import ai.ecoinference.app.ui.theme.EcoColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.TimeZone
import java.util.concurrent.TimeUnit

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
        description = "\"12 × 12\" → result contains 144",
        expectedKind = ResultKind.Text,
        mustContain  = listOf("144"),
        e2ePrompt    = "what is 12 multiplied by 12",
    ),

    // ── Python E2E: sine wave plot ────────────────────────────────────────────
    TestCase(
        id = "py_e2e_sine_plot",
        name = "Python E2E — sine wave plot",
        description = "\"plot a sine wave\" → PNG image or interactive HTML",
        expectedKind = ResultKind.Image,
        altKind      = ResultKind.Html,
        e2ePrompt    = "plot a sine wave from 0 to 2 pi",
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
        if (_running.value) return
        viewModelScope.launch {
            _running.value      = true
            _currentIndex.value = 0
            _states.value       = TEST_CASES.map { TestState(it) }

            val preamble  = fetchGpsPreamble(context)
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

        val systemPrompt = buildString {
            val userSys = appState.settings.systemPrompt()
            if (userSys.isNotBlank()) appendLine(userSys)
            appendLine(ToolRegistry.systemPromptBlock())
        }.trim()

        val messages = buildList {
            if (systemPrompt.isNotBlank())
                add(InferenceMessage(role = "system", text = systemPrompt))
            add(InferenceMessage(role = "user", text = tc.e2ePrompt!!))
        }
        val textBuf  = StringBuilder()
        var lastImage: ByteArray? = null

        runAgentLoop(messages = messages, inference = inference).collect { token ->
            when (token) {
                is AgentToken.Text       -> textBuf.append(token.chunk)
                is AgentToken.ChartImage -> lastImage = token.bytes
            }
        }

        val elapsed = System.currentTimeMillis() - startMs

        val result: ToolResult = if (lastImage != null)
            ToolResult.Image(lastImage, "chart")
        else
            ToolResult.Text(textBuf.toString())
        return evaluate(tc, result).copy(elapsedMs = elapsed)
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

        // Error markers
        if (content.startsWith("{\"error\"") ||
            content.contains("Traceback (most recent call last)") ||
            content.startsWith("Error:")) {
            return TestState(tc, TestStatus.Failed, content.take(400))
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
                "Expected $expected, got ${actualKind.name}.\n${content.take(200)}",
            )
        }

        // mustContain checks (case-insensitive)
        val lower = content.lowercase()
        for (kw in tc.mustContain) {
            if (!lower.contains(kw.lowercase())) {
                return TestState(
                    tc, TestStatus.Failed,
                    "Missing \"$kw\" in result.\n${content.take(200)}",
                )
            }
        }

        // mustNotContain checks
        for (kw in tc.mustNotContain) {
            if (lower.contains(kw.lowercase())) {
                return TestState(
                    tc, TestStatus.Failed,
                    "Unexpected \"$kw\" found in result.\n${content.take(200)}",
                )
            }
        }

        // Pass — store a short preview
        val preview = when (actualKind) {
            ResultKind.Image -> content
            ResultKind.Html  -> "[HTML ${content.length / 1024} KB — OK]"
            ResultKind.Text  -> content.take(200).let { if (content.length > 200) "$it…" else it }
        }
        return TestState(tc, TestStatus.Passed, preview)
    }

    // ── State helpers ─────────────────────────────────────────────────────────

    private fun updateState(index: Int, transform: (TestState) -> TestState) {
        _states.value = _states.value.toMutableList().also { it[index] = transform(it[index]) }
    }
}

// ── GPS preamble ──────────────────────────────────────────────────────────────

@SuppressLint("MissingPermission")
private suspend fun fetchGpsPreamble(context: Context): String =
    withContext(Dispatchers.IO) {
        try {
            val client = LocationServices.getFusedLocationProviderClient(context)
            val loc    = Tasks.await(
                client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null),
                5, TimeUnit.SECONDS,
            )
            val tz     = TimeZone.getDefault()
            val offset = tz.rawOffset / 3_600_000.0
            if (loc != null)
                buildPreamble(loc.latitude, loc.longitude, tz.id, offset)
            else
                defaultPreamble()
        } catch (e: Exception) {
            Log.w(TAG, "GPS unavailable, using fallback coords: ${e.message}")
            defaultPreamble()
        }
    }

private fun buildPreamble(lat: Double, lon: Double, tzId: String, tzOffset: Double) =
    "user_latitude = $lat\nuser_longitude = $lon\nuser_timezone = \"$tzId\"\nuser_timezone_offset = $tzOffset\n"

private fun defaultPreamble() =
    buildPreamble(41.8450, -91.7026, "America/Chicago", -6.0)

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PythonTestScreen(
    appState: AppState,
    modifier: Modifier = Modifier,
    vm: PythonTestViewModel = viewModel(),
) {
    val context      = LocalContext.current
    val states       by vm.states.collectAsState()
    val running      by vm.running.collectAsState()
    val currentIndex by vm.currentIndex.collectAsState()

    val passed  = states.count { it.status == TestStatus.Passed }
    val failed  = states.count { it.status == TestStatus.Failed }
    val skipped = states.count { it.status == TestStatus.Skipped }

    Scaffold(
        modifier            = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title  = { Text("Python Tool Tests") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
                actions = {
                    if (running) {
                        Box(
                            modifier          = Modifier.padding(horizontal = 16.dp),
                            contentAlignment  = Alignment.Center,
                        ) {
                            CircularProgressIndicator(
                                modifier    = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color       = EcoColors.Green,
                            )
                        }
                    } else {
                        IconButton(onClick = { vm.runAll(context, appState) }) {
                            Icon(
                                Icons.Default.PlayCircleOutline,
                                contentDescription = "Run all tests",
                                tint               = EcoColors.Green,
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
            SummaryBar(passed = passed, failed = failed, skipped = skipped, total = states.size)

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
private fun SummaryBar(passed: Int, failed: Int, skipped: Int, total: Int) {
    Surface(
        color    = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier            = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment   = Alignment.CenterVertically,
        ) {
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
                color = EcoColors.NearWhite.copy(alpha = 0.6f),
            )
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
        tc.isPythonE2E       -> "Python"    to EcoColors.Green
        else                 -> "Python"    to EcoColors.Green
    }

    val (icon, iconColor) = when (state.status) {
        TestStatus.Pending -> Icons.Default.RadioButtonUnchecked to Color.Gray
        TestStatus.Running -> Icons.Default.HourglassTop         to EcoColors.Green
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
                        color       = EcoColors.Green,
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
                                else               -> EcoColors.NearWhite
                            },
                        )
                    }
                    Text(
                        subtitleText,
                        style    = MaterialTheme.typography.bodySmall,
                        color    = EcoColors.NearWhite.copy(alpha = 0.5f),
                        maxLines = 1,
                    )
                }

                // Chevron
                if (state.detail.isNotEmpty()) {
                    Text(
                        if (expanded) "▲" else "▼",
                        style    = MaterialTheme.typography.labelSmall,
                        color    = EcoColors.DimGreen,
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
                        else               -> EcoColors.NearWhite.copy(alpha = 0.7f)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 44.dp, end = 12.dp, bottom = 12.dp),
                )
            }
        }
    }
}
