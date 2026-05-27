package ai.ecoinference.app.tools

import android.util.Log
import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private val TOOL_CALL_RE = Regex("<tool_call>(.*?)</tool_call>", RegexOption.DOT_MATCHES_ALL)
private const val MAX_TOOL_ITERATIONS = 5
private const val TAG = "AgentLoop"
private val jsonParser = Json { ignoreUnknownKeys = true }

/**
 * Runs the agentic tool-call loop.
 *
 * Tool-call turns are buffered silently — the raw <tool_call> JSON and
 * [Tool:] / [Result:] markers are never shown to the user.
 * Only the final clean response (no tool call) is emitted to the UI.
 */
fun runAgentLoop(
    messages:     List<InferenceMessage>,
    inference:    InferenceService,
    maxTokens:    Int   = 2048,
    temperature:  Float = 0.8f,
): Flow<String> = flow {
    val history = messages.toMutableList()
    var iterations = 0

    Log.d(TAG, "runAgentLoop start — ${history.size} messages, tools=${ToolRegistry.all().map { it.name }}")

    while (iterations < MAX_TOOL_ITERATIONS) {
        Log.d(TAG, "Iteration $iterations — calling chatStream")

        // Buffer the response silently — never emit tool-call scaffolding to the UI
        val sb = StringBuilder()
        inference.chatStream(history, maxTokens, temperature).collect { token ->
            sb.append(token)
        }
        val response = sb.toString().trim()
        Log.d(TAG, "Model response (iter=$iterations):\n$response")

        val match = TOOL_CALL_RE.find(response)
        if (match == null) {
            // No tool call — this is the final clean answer; emit it now
            Log.d(TAG, "No <tool_call> found — emitting final response")
            emit(response)
            break
        }

        // Tool call found — parse and execute silently
        val raw = match.groupValues[1].trim()
        Log.d(TAG, "Raw tool_call content: $raw")

        val parsed = parseToolCall(raw)
        if (parsed == null) {
            Log.e(TAG, "Failed to parse tool call: $raw")
            emit("Sorry, I couldn't parse the tool call.")
            break
        }

        val (toolName, toolArgs) = parsed
        Log.d(TAG, "Parsed → name=$toolName  args=$toolArgs")

        val tool = ToolRegistry.find(toolName)
        if (tool == null) {
            Log.e(TAG, "Unknown tool: $toolName")
            emit("Sorry, I tried to use an unknown tool: $toolName.")
            break
        }

        val result = try {
            tool.execute(toolArgs).also { Log.d(TAG, "Tool result: $it") }
        } catch (e: Exception) {
            Log.e(TAG, "Tool execution error: ${e.message}")
            "Error: ${e.message}"
        }

        // Inject tool result into history and continue
        history += InferenceMessage(role = "assistant", text = response)
        history += InferenceMessage(
            role = "user",
            text = "<tool_result>{\"name\":\"$toolName\",\"result\":${
                kotlinx.serialization.json.Json.encodeToString(
                    kotlinx.serialization.json.JsonPrimitive.serializer(),
                    kotlinx.serialization.json.JsonPrimitive(result)
                )
            }}</tool_result>",
        )

        iterations++
    }

    Log.d(TAG, "runAgentLoop done after $iterations iteration(s)")
}

/**
 * Parses the content between <tool_call> tags into (toolName, argsJson).
 *
 * Handles two formats Gemma 4 may produce:
 *   1. Canonical JSON:  {"name":"web_search","args":{"query":"..."}}
 *   2. Shorthand:       web_search{"query":"..."} or web_search{query:"..."}
 */
private fun parseToolCall(raw: String): Pair<String, String>? {
    // Format 1: starts with { — canonical {"name":...,"args":...}
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

    // Format 2: shorthand  tool_name{...}
    val braceIdx = raw.indexOf('{')
    if (braceIdx > 0) {
        val toolName  = raw.substring(0, braceIdx).trim()
        val rawArgs   = raw.substring(braceIdx).trim()
        val fixedArgs = normaliseJsonKeys(rawArgs)
        return try {
            jsonParser.parseToJsonElement(fixedArgs)
            Pair(toolName, fixedArgs)
        } catch (e: Exception) {
            Log.e(TAG, "Shorthand parse failed for args '$fixedArgs': ${e.message}")
            Pair(toolName, "{}")
        }
    }

    // Format 3: bare tool name with no args
    val bare = raw.trim()
    if (bare.isNotBlank() && !bare.contains(" ")) return Pair(bare, "{}")

    return null
}

/** Adds double-quotes around unquoted JSON object keys. */
private fun normaliseJsonKeys(json: String): String =
    json.replace(Regex("([{,]\\s*)([a-zA-Z_][a-zA-Z0-9_]*)\\s*:")) { mr ->
        "${mr.groupValues[1]}\"${mr.groupValues[2]}\":"
    }
