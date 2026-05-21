package com.gemma4.aiserver.server.routes

import com.gemma4.aiserver.inference.InferenceMessage
import com.gemma4.aiserver.inference.InferenceRepository
import com.gemma4.aiserver.model.ChatChoice
import com.gemma4.aiserver.model.ChatChunk
import com.gemma4.aiserver.model.ChatCompletionRequest
import com.gemma4.aiserver.model.ChatCompletionResponse
import com.gemma4.aiserver.model.ChatMessage
import com.gemma4.aiserver.model.ChunkChoice
import com.gemma4.aiserver.model.ChunkDelta
import com.gemma4.aiserver.model.CompletionChoice
import com.gemma4.aiserver.model.CompletionRequest
import com.gemma4.aiserver.model.CompletionResponse
import com.gemma4.aiserver.model.ErrorResponse
import com.gemma4.aiserver.model.TokenUsage
import com.gemma4.aiserver.model.extractImageBytes
import com.gemma4.aiserver.model.extractText
import kotlinx.serialization.json.JsonPrimitive
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.response.respondBytesWriter
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import io.ktor.utils.io.writeStringUtf8
import kotlinx.coroutines.flow.catch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

fun Route.inferenceRoutes(
    inference: InferenceRepository,
) {

    // ── Chat completions ──────────────────────────────────────────────────────

    /**
     * POST /v1/chat/completions
     *
     * OpenAI-compatible chat completions endpoint.
     * Set `"stream": true` in the request body to receive a token-by-token
     * SSE stream; omit (or set false) for a single JSON response.
     */
    post("/v1/chat/completions") {
        val req = runCatching { call.receive<ChatCompletionRequest>() }.getOrNull()
            ?: return@post call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Invalid request body"),
            )

        if (!inference.isLoaded) {
            return@post call.respond(
                HttpStatusCode.ServiceUnavailable,
                ErrorResponse("No model loaded. POST /v1/models/load first."),
            )
        }

        // Map HTTP messages → InferenceMessage, extracting text and any image attachment.
        val messages = req.messages.map { msg ->
            InferenceMessage(
                role       = msg.role,
                text       = msg.extractText(),
                imageBytes = msg.extractImageBytes(),
            )
        }
        val id = "chatcmpl-${UUID.randomUUID()}"

        if (req.stream) {
            // ── Streaming path ────────────────────────────────────────────────
            call.respondBytesWriter(contentType = ContentType.Text.EventStream) {
                // Outer try-catch ensures any exception that escapes the flow's
                // own .catch block still produces a structured error event rather
                // than silently closing the socket (which the client sees as
                // "Connection closed while receiving data").
                try {
                    // Role delta — sent once at the start
                    val roleChunk = ChatChunk(
                        id = id,
                        model = req.model,
                        choices = listOf(
                            ChunkChoice(delta = ChunkDelta(role = "assistant")),
                        ),
                    )
                    writeStringUtf8("data: ${Json.encodeToString(roleChunk)}\n\n")
                    flush()

                    // Content deltas — one per token/partial token
                    inference.chatStream(
                        messages = messages,
                        maxTokens = req.maxTokens,
                        temperature = req.temperature,
                    ).catch { e ->
                        // Emit an error chunk so the client knows what went wrong.
                        android.util.Log.e("InferenceRoutes", "chatStream error", e)
                        val errChunk = ChatChunk(
                            id = id,
                            model = req.model,
                            choices = listOf(
                                ChunkChoice(
                                    delta = ChunkDelta(content = "[ERROR: ${e.message}]"),
                                    finishReason = "error",
                                ),
                            ),
                        )
                        writeStringUtf8("data: ${Json.encodeToString(errChunk)}\n\n")
                        flush()
                    }.collect { token ->
                        val chunk = ChatChunk(
                            id = id,
                            model = req.model,
                            choices = listOf(
                                ChunkChoice(delta = ChunkDelta(content = token)),
                            ),
                        )
                        writeStringUtf8("data: ${Json.encodeToString(chunk)}\n\n")
                        flush()
                    }

                    // Stop delta — signals end of generation
                    val stopChunk = ChatChunk(
                        id = id,
                        model = req.model,
                        choices = listOf(
                            ChunkChoice(delta = ChunkDelta(), finishReason = "stop"),
                        ),
                    )
                    writeStringUtf8("data: ${Json.encodeToString(stopChunk)}\n\n")
                    writeStringUtf8("data: [DONE]\n\n")
                    flush()
                } catch (e: Exception) {
                    android.util.Log.e("InferenceRoutes", "Unhandled SSE exception", e)
                    runCatching {
                        val errChunk = ChatChunk(
                            id = id,
                            model = req.model,
                            choices = listOf(
                                ChunkChoice(
                                    delta = ChunkDelta(content = "[ERROR: ${e.message}]"),
                                    finishReason = "error",
                                ),
                            ),
                        )
                        writeStringUtf8("data: ${Json.encodeToString(errChunk)}\n\n")
                        writeStringUtf8("data: [DONE]\n\n")
                        flush()
                    }
                }
            }
        } else {
            // ── Non-streaming path ────────────────────────────────────────────
            runCatching {
                inference.chat(
                    messages = messages,
                    maxTokens = req.maxTokens,
                    temperature = req.temperature,
                )
            }.fold(
                onSuccess = { output ->
                    val promptTokens = estimateTokens(
                        req.messages.joinToString(" ") { it.extractText() }
                    )
                    val completionTokens = estimateTokens(output)
                    call.respond(
                        ChatCompletionResponse(
                            id = id,
                            model = req.model,
                            choices = listOf(
                                ChatChoice(
                                    message = ChatMessage(
                                        role    = "assistant",
                                        content = JsonPrimitive(output),
                                    ),
                                ),
                            ),
                            usage = TokenUsage(
                                promptTokens = promptTokens,
                                completionTokens = completionTokens,
                                totalTokens = promptTokens + completionTokens,
                            ),
                        )
                    )
                },
                onFailure = { e ->
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(e.message ?: "Inference failed"),
                    )
                },
            )
        }
    }

    // ── Text completions ──────────────────────────────────────────────────────

    /**
     * POST /v1/completions
     *
     * OpenAI-compatible single-turn text completion endpoint.
     * Wraps the prompt in a single user turn and delegates to the same
     * underlying inference engine as /v1/chat/completions.
     */
    post("/v1/completions") {
        val req = runCatching { call.receive<CompletionRequest>() }.getOrNull()
            ?: return@post call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Invalid request body"),
            )

        if (!inference.isLoaded) {
            return@post call.respond(
                HttpStatusCode.ServiceUnavailable,
                ErrorResponse("No model loaded. POST /v1/models/load first."),
            )
        }

        val id = "cmpl-${UUID.randomUUID()}"

        if (req.stream) {
            // ── Streaming path ────────────────────────────────────────────────
            call.respondBytesWriter(contentType = ContentType.Text.EventStream) {
                inference.completeStream(
                    prompt = req.prompt,
                    maxTokens = req.maxTokens,
                    temperature = req.temperature,
                ).catch { e ->
                    writeStringUtf8("data: [ERROR: ${e.message}]\n\n")
                    flush()
                }.collect { token ->
                    // Mirror the OpenAI /v1/completions shape for client compatibility.
                    val chunk = CompletionResponse(
                        id = id,
                        model = req.model,
                        choices = listOf(CompletionChoice(text = token, finishReason = "")),
                        usage = TokenUsage(0, 0, 0),
                    )
                    writeStringUtf8("data: ${Json.encodeToString(chunk)}\n\n")
                    flush()
                }
                writeStringUtf8("data: [DONE]\n\n")
                flush()
            }
        } else {
            // ── Non-streaming path ────────────────────────────────────────────
            runCatching {
                inference.complete(
                    prompt = req.prompt,
                    maxTokens = req.maxTokens,
                    temperature = req.temperature,
                )
            }.fold(
                onSuccess = { output ->
                    val promptTokens = estimateTokens(req.prompt)
                    val completionTokens = estimateTokens(output)
                    call.respond(
                        CompletionResponse(
                            id = id,
                            model = req.model,
                            choices = listOf(
                                CompletionChoice(text = output),
                            ),
                            usage = TokenUsage(
                                promptTokens = promptTokens,
                                completionTokens = completionTokens,
                                totalTokens = promptTokens + completionTokens,
                            ),
                        )
                    )
                },
                onFailure = { e ->
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(e.message ?: "Inference failed"),
                    )
                },
            )
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Rough token count: ~4 chars per token (common GPT/Gemma heuristic).
 * Good enough for usage reporting; not used for budget enforcement.
 */
private fun estimateTokens(text: String): Int = (text.length / 4).coerceAtLeast(1)
