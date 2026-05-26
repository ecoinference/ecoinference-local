package ai.ecoinference.app.tools

import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private val TOOL_CALL_RE = Regex("<tool_call>(.*?)</tool_call>", RegexOption.DOT_MATCHES_ALL)
private const val MAX_TOOL_ITERATIONS = 5
private val jsonParser = Json { ignoreUnknownKeys = true }

/**
 * Runs the agentic tool-call loop.
 *
 * After the model emits a response, checks for `<tool_call>…</tool_call>` blocks.
 * If found: parses the JSON, executes the tool via [ToolRegistry], injects the
 * result as a user message, and runs the model again — up to [MAX_TOOL_ITERATIONS].
 *
 * Emits tokens as they arrive. Tool execution steps emit a synthetic
 * "[Tool: name]" and "[Result: …]" marker so the UI can show progress.
 *
 * Mirrors iOS AgentLoop.swift.
 */
fun runAgentLoop(
    messages:     List<InferenceMessage>,
    inference:    InferenceService,
    maxTokens:    Int   = 2048,
    temperature:  Float = 0.8f,
): Flow<String> = flow {
    val history = messages.toMutableList()
    var iterations = 0

    while (iterations < MAX_TOOL_ITERATIONS) {
        // Collect full response for this turn (tool detection needs the full text)
        val sb = StringBuilder()
        inference.chatStream(history, maxTokens, temperature).collect { token ->
            sb.append(token)
            emit(token)
        }
        val response = sb.toString().trim()

        // Check for tool call
        val match = TOOL_CALL_RE.find(response) ?: break   // no tool call → done

        val toolJson = match.groupValues[1].trim()
        val toolName: String
        val toolArgs: String

        try {
            val obj    = jsonParser.parseToJsonElement(toolJson).jsonObject
            toolName   = obj["name"]?.jsonPrimitive?.content
                ?: throw IllegalArgumentException("missing 'name'")
            toolArgs   = obj["args"]?.jsonObject?.toString() ?: "{}"
        } catch (e: Exception) {
            emit("\n[Tool parse error: ${e.message}]")
            break
        }

        val tool = ToolRegistry.find(toolName)
        if (tool == null) {
            emit("\n[Unknown tool: $toolName]")
            break
        }

        emit("\n[Tool: $toolName]\n")
        val result = try {
            tool.execute(toolArgs)
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
        emit("[Result: $result]\n")

        // Add the assistant response and tool result to history, then continue
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
}
