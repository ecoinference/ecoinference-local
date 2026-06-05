package ai.ecoinference.app.tools

import android.util.Log
import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// ── Tool-call regexes ─────────────────────────────────────────────────────────

// Format A — system-prompt-injected style:  <tool_call>...</tool_call>
private val TOOL_CALL_RE = Regex("<tool_call>(.*?)</tool_call>", RegexOption.DOT_MATCHES_ALL)

// Format B — Gemma 4 native tokens:  <|tool_call>call:TOOL{...}<tool_call|>
// The model uses <|"|> as a string-value delimiter instead of JSON quotes.
private val NATIVE_CALL_RE = Regex("<\\|tool_call>(.*?)<tool_call\\|>", RegexOption.DOT_MATCHES_ALL)

// Gemma 4 special tokens to strip from any final response shown to the user.
private val SPECIAL_TOKEN_RE = Regex("<\\|[^|>]*\\|?>")

private const val MAX_TOOL_ITERATIONS = 5
private const val TAG = "AgentLoop"
private val jsonParser = Json { ignoreUnknownKeys = true }

/**
 * Runs the agentic tool-call loop.
 *
 * Supports two tool-call formats Gemma 4 may produce:
 *   A) System-prompt style:  <tool_call>{"name":"...","args":{...}}</tool_call>
 *   B) Native token style:   <|tool_call>call:TOOL{key:<|"|>value<|"|>}<tool_call|>
 *
 * Tool-call turns are buffered silently.  Only the final clean response
 * (with all special tokens stripped) is emitted to the UI.
 *
 * Emits [AgentToken.Text] for text and [AgentToken.ChartImage] for images.
 */
fun runAgentLoop(
    messages:     List<InferenceMessage>,
    inference:    InferenceService,
    maxTokens:    Int   = 2048,
    temperature:  Float = 0.8f,
): Flow<AgentToken> = flow {
    val history       = messages.toMutableList()
    val pendingCharts = mutableListOf<AgentToken.ChartImage>()
    var iterations    = 0

    Log.d(TAG, "runAgentLoop start — ${history.size} messages, tools=${ToolRegistry.all().map { it.name }}")

    while (iterations < MAX_TOOL_ITERATIONS) {
        Log.d(TAG, "Iteration $iterations — calling chatStream")

        val sb = StringBuilder()
        inference.chatStream(history, maxTokens, temperature).collect { token -> sb.append(token) }
        val response = sb.toString().trim()
        Log.d(TAG, "Model response (iter=$iterations):\n$response")

        // Try format A first, then format B
        val (matchRaw, nativeFormat) = run {
            val a = TOOL_CALL_RE.find(response)
            if (a != null) Pair(a.groupValues[1].trim(), false)
            else {
                val b = NATIVE_CALL_RE.find(response)
                if (b != null) Pair(b.groupValues[1].trim(), true) else Pair(null, false)
            }
        }

        if (matchRaw == null) {
            // No tool call — strip special tokens and emit final response.
            val clean = SPECIAL_TOKEN_RE.replace(response, "").trim()
            Log.d(TAG, "No tool call — emitting final response (cleaned)")
            emit(AgentToken.Text(clean))
            pendingCharts.forEach { emit(it) }
            break
        }

        Log.d(TAG, "Tool call found (native=$nativeFormat): $matchRaw")

        val parsed = if (nativeFormat) parseNativeToolCall(matchRaw) else parseToolCall(matchRaw)
        if (parsed == null) {
            Log.e(TAG, "Failed to parse tool call: $matchRaw")
            emit(AgentToken.Text("Sorry, I couldn't parse the tool call."))
            break
        }

        val (toolName, toolArgs) = parsed
        Log.d(TAG, "Parsed → name=$toolName  args=$toolArgs")

        val tool = ToolRegistry.find(toolName)
        if (tool == null) {
            Log.e(TAG, "Unknown tool: $toolName")
            emit(AgentToken.Text("Sorry, I tried to use an unknown tool: $toolName."))
            break
        }

        val result: ToolResult = try {
            tool.execute(toolArgs).also { Log.d(TAG, "Tool result: ${it.modelText().take(200)}") }
        } catch (e: Exception) {
            Log.e(TAG, "Tool execution error: ${e.message}")
            ToolResult.Text("Error: ${e.message}")
        }

        if (result is ToolResult.Image) {
            pendingCharts += AgentToken.ChartImage(result.bytes, result.caption)
        }

        history += InferenceMessage(role = "assistant", text = response)
        history += InferenceMessage(
            role = "user",
            text = "<tool_result>{\"name\":\"$toolName\",\"result\":${
                Json.encodeToString(
                    kotlinx.serialization.json.JsonPrimitive.serializer(),
                    kotlinx.serialization.json.JsonPrimitive(result.modelText())
                )
            }}</tool_result>",
        )

        iterations++
    }

    if (iterations >= MAX_TOOL_ITERATIONS) {
        emit(AgentToken.Text("(Reached maximum tool iterations without a final answer.)"))
    }

    Log.d(TAG, "runAgentLoop done after $iterations iteration(s)")
}

// ── Format A parser ───────────────────────────────────────────────────────────

/**
 * Parses the content between <tool_call> tags into (toolName, argsJson).
 *
 * Handles:
 *   1. Canonical JSON:  {"name":"tool","args":{"param":"value"}}
 *   2. Shorthand:       tool_name{"param":"value"}
 *   3. Bare name:       tool_name
 */
private fun parseToolCall(raw: String): Pair<String, String>? {
    if (raw.startsWith("{")) {
        return try {
            val obj      = jsonParser.parseToJsonElement(raw).jsonObject
            val toolName = obj["name"]?.jsonPrimitive?.content ?: return null
            val toolArgs = obj["args"]?.jsonObject?.toString() ?: "{}"
            Pair(toolName, toolArgs)
        } catch (e: Exception) {
            Log.e(TAG, "Canonical JSON parse failed: ${e.message}")
            null
        }
    }

    val braceIdx = raw.indexOf('{')
    if (braceIdx > 0) {
        val toolName  = raw.substring(0, braceIdx).trim()
        val rawArgs   = raw.substring(braceIdx).trim()
        val fixedArgs = normaliseJsonKeys(rawArgs)
        return try {
            jsonParser.parseToJsonElement(fixedArgs)
            Pair(toolName, fixedArgs)
        } catch (e: Exception) {
            Log.e(TAG, "Shorthand parse failed for '$fixedArgs': ${e.message}")
            Pair(toolName, "{}")
        }
    }

    val bare = raw.trim()
    if (bare.isNotBlank() && !bare.contains(" ")) return Pair(bare, "{}")
    return null
}

// ── Format B parser (Gemma 4 native) ─────────────────────────────────────────

/**
 * Parses Gemma 4 native tool-call content into (toolName, argsJson).
 *
 * Input example:
 *   call:run_python{code:<|"|>import numpy as np\nresult = np.sqrt(2)<|"|>}
 *
 * Strategy:
 *   1. Strip leading "call:" prefix.
 *   2. Extract tool name (everything before the first '{').
 *   3. Convert <|"|>value<|"|> spans to properly JSON-escaped "value" strings.
 *   4. Parse the resulting JSON object.
 */
private fun parseNativeToolCall(raw: String): Pair<String, String>? {
    val withoutPrefix = if (raw.startsWith("call:")) raw.removePrefix("call:") else raw

    val braceIdx = withoutPrefix.indexOf('{')
    if (braceIdx < 0) {
        // Bare tool name
        val name = withoutPrefix.trim()
        return if (name.isNotBlank()) Pair(name, "{}") else null
    }

    val toolName = withoutPrefix.substring(0, braceIdx).trim()
    val argsRaw  = withoutPrefix.substring(braceIdx)

    // Convert <|"|>....<|"|> spans to JSON-escaped "..." strings
    val argsJson = convertNativeStrings(argsRaw)
    Log.d(TAG, "Native args converted: $argsJson")

    val fixedArgs = normaliseJsonKeys(argsJson)
    return try {
        jsonParser.parseToJsonElement(fixedArgs)
        Pair(toolName, fixedArgs)
    } catch (e: Exception) {
        Log.e(TAG, "Native args parse failed for '$fixedArgs': ${e.message}")
        // Return with raw args as the "code" field as a fallback
        Pair(toolName, "{}")
    }
}

/**
 * Replaces Gemma 4's <|"|>value<|"|> string delimiters with
 * properly JSON-escaped "value" strings.
 */
private fun convertNativeStrings(s: String): String {
    val delim = "<|\"|>"
    val result = StringBuilder()
    var i = 0
    while (i < s.length) {
        val dStart = s.indexOf(delim, i)
        if (dStart < 0) { result.append(s.substring(i)); break }
        result.append(s.substring(i, dStart))
        result.append('"')
        val dEnd = s.indexOf(delim, dStart + delim.length)
        if (dEnd < 0) { result.append(s.substring(dStart + delim.length)); break }
        // Escape the string value for JSON
        val value = s.substring(dStart + delim.length, dEnd)
        result.append(
            value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t")
        )
        result.append('"')
        i = dEnd + delim.length
    }
    return result.toString()
}

/** Adds double-quotes around unquoted JSON object keys. */
private fun normaliseJsonKeys(json: String): String =
    json.replace(Regex("([{,]\\s*)([a-zA-Z_][a-zA-Z0-9_]*)\\s*:")) { mr ->
        "${mr.groupValues[1]}\"${mr.groupValues[2]}\":"
    }
