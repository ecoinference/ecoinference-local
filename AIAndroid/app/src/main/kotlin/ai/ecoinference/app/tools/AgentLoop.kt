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
        // Lightweight benchmark — Android has no native benchmark hook (unlike
        // iOS's litert_lm_conversation_get_benchmark_info), so approximate via
        // wall-clock timing around the token stream. Each streamed "token" may
        // actually be a multi-token chunk, so decode tok/s here is a chunk-rate
        // floor, not an exact token rate.
        val startNanos = System.nanoTime()
        var firstTokenNanos = 0L
        var chunkCount = 0
        inference.chatStream(history, maxTokens, temperature).collect { token ->
            if (chunkCount == 0) firstTokenNanos = System.nanoTime()
            chunkCount++
            sb.append(token)
        }
        val endNanos = System.nanoTime()
        val ttftMs = (firstTokenNanos - startNanos) / 1_000_000.0
        val decodeMs = (endNanos - firstTokenNanos) / 1_000_000.0
        val decodeRate = if (decodeMs > 0 && chunkCount > 1) (chunkCount - 1) * 1000.0 / decodeMs else 0.0
        Log.i(TAG, "benchmark: TTFT=%.3fs  decode=%.1f chunks/s (%d chunks, %.3fs total)"
            .format(ttftMs / 1000.0, decodeRate, chunkCount, (endNanos - startNanos) / 1_000_000_000.0))
        val response = sb.toString().trim()
        Log.d(TAG, "Model response (iter=$iterations):\n$response")

        // Try format A first, then format B
        val (matchRaw, nativeFormat) = run {
            val a = TOOL_CALL_RE.find(response)
            if (a != null) return@run Pair(a.groupValues[1].trim(), false)
            val b = NATIVE_CALL_RE.find(response)
            if (b != null) return@run Pair(b.groupValues[1].trim(), true)

            // Neither regex matched — likely a missing/malformed closing tag
            // (model truncated or hallucinated something other than the close
            // tag, e.g. a stray "/>"). Fall back to "from opening tag to end of
            // string" so the repair pipeline in parseToolCall/parseNativeToolCall
            // gets a chance to recover it instead of giving up immediately.
            val openA = response.indexOf("<tool_call>")
            if (openA >= 0) {
                return@run Pair(response.substring(openA + "<tool_call>".length).trim(), false)
            }
            val openB = response.indexOf("<|tool_call>")
            if (openB >= 0) {
                return@run Pair(response.substring(openB + "<|tool_call>".length).trim(), true)
            }
            Pair(null, false)
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

        when (result) {
            is ToolResult.Image -> pendingCharts += AgentToken.ChartImage(result.bytes, result.caption)
            is ToolResult.Text  -> emit(AgentToken.ToolText(result.text))
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
        // Don't just give up — run one more no-more-tools turn so the user
        // gets a real answer from whatever was gathered, instead of a static
        // placeholder (mirrors iOS AgentLoop/ChatView's forced-final turn).
        Log.d(TAG, "Tool budget exhausted after $iterations iterations — forcing final turn")
        history += InferenceMessage(
            role = "user",
            text = "(Tool budget exhausted. Answer now using only the information gathered above; " +
                "if it is insufficient, say what is missing.)",
        )
        val sb = StringBuilder()
        inference.chatStream(history, maxTokens, temperature).collect { token -> sb.append(token) }
        val finalResponse = sb.toString().trim()
        if (TOOL_CALL_RE.containsMatchIn(finalResponse) || NATIVE_CALL_RE.containsMatchIn(finalResponse)) {
            // Model ignored the nudge — still never show a raw tool-call fragment.
            Log.e(TAG, "Forced-final turn still contained a tool call")
            emit(AgentToken.Text("I wasn't able to finish that within the tool budget — please try rephrasing."))
        } else {
            emit(AgentToken.Text(SPECIAL_TOKEN_RE.replace(finalResponse, "").trim()))
        }
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
        // Multi-attempt parse, each step progressively more aggressive at repair —
        // mirrors iOS AgentLoop.swift. Most responses parse on the first try;
        // the later steps only kick in for malformed/truncated tool calls
        // (e.g. a stray "/>" where the model should have closed the JSON).
        tryParseCanonical(raw)?.let { return it }
        val escaped = escapeControlCharsInStrings(raw)
        tryParseCanonical(escaped)?.let { return it }
        val sanitized = sanitizeStructuralGarbage(escaped)
        tryParseCanonical(sanitized)?.let { return it }
        val closed = autoCloseJson(sanitized)
        tryParseCanonical(closed)?.let { return it }
        Log.e(TAG, "Canonical JSON parse failed after all repair attempts: $raw")
        return null
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

private fun tryParseCanonical(raw: String): Pair<String, String>? = try {
    val obj      = jsonParser.parseToJsonElement(raw).jsonObject
    val toolName = obj["name"]?.jsonPrimitive?.content ?: return null
    val toolArgs = obj["args"]?.jsonObject?.toString() ?: "{}"
    Pair(toolName, toolArgs)
} catch (e: Exception) {
    null
}

// ── JSON repair helpers (mirror iOS AgentLoop.swift) ──────────────────────────

/** Escapes literal control characters (newline, tab, CR) inside JSON string values. */
private fun escapeControlCharsInStrings(s: String): String {
    val result = StringBuilder()
    var inString = false
    var escaped = false
    for (ch in s) {
        if (escaped) { result.append(ch); escaped = false; continue }
        if (ch == '\\' && inString) { result.append(ch); escaped = true; continue }
        if (ch == '"') { inString = !inString; result.append(ch); continue }
        if (inString) {
            when (ch) {
                '\n' -> result.append("\\n")
                '\r' -> result.append("\\r")
                '\t' -> result.append("\\t")
                else -> result.append(ch)
            }
        } else {
            result.append(ch)
        }
    }
    return result.toString()
}

/**
 * Strips characters outside string literals that aren't valid JSON
 * structural/whitespace/value characters (e.g. a stray '/' or '>' from the
 * model blending in XML/HTML tag syntax instead of closing the JSON).
 * No-op on well-formed JSON.
 */
private fun sanitizeStructuralGarbage(s: String): String {
    val allowed = "{}[]:,\"-+.eE0123456789truefalsenull \t\n\r".toSet()
    val result = StringBuilder()
    var inString = false
    var escaped = false
    for (ch in s) {
        if (escaped) { result.append(ch); escaped = false; continue }
        if (ch == '\\' && inString) { result.append(ch); escaped = true; continue }
        if (ch == '"') { inString = !inString; result.append(ch); continue }
        if (inString) { result.append(ch); continue }
        if (ch in allowed) result.append(ch)
        // else: drop — not valid outside a JSON string literal.
    }
    return result.toString()
}

/** Appends missing closing braces/brackets to truncated JSON. */
private fun autoCloseJson(s: String): String {
    val stack = mutableListOf<Char>()
    var inString = false
    var escaped = false
    for (ch in s) {
        if (escaped) { escaped = false; continue }
        if (ch == '\\' && inString) { escaped = true; continue }
        if (ch == '"') { inString = !inString; continue }
        if (inString) continue
        when (ch) {
            '{' -> stack.add('}')
            '[' -> stack.add(']')
            '}', ']' -> if (stack.isNotEmpty()) stack.removeAt(stack.size - 1)
        }
    }
    return s + stack.asReversed().joinToString("")
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
