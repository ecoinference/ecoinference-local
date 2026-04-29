import Foundation

// MARK: - Route registration

func registerInferenceRoutes(router: Router) {
    registerChatCompletions(router: router)
    registerCompletions(router: router)
}

// MARK: - POST /v1/chat/completions

private func registerChatCompletions(router: Router) {
    router.add("POST", "/v1/chat/completions") { request in
        guard let req = try? request.decode(ChatCompletionRequest.self) else {
            return HttpResponse.error("Invalid JSON body", status: 400)
        }

        let inference = InferenceService.shared
        guard inference.isLoaded else {
            return HttpResponse.error("No model loaded. Call /v1/models/load first.", status: 503)
        }

        let messages = req.messages.map { ["role": $0.role, "content": $0.content] }
        let modelId  = inference.loadedModelId ?? req.model

        if req.stream {
            // ── Streaming SSE ─────────────────────────────────────────────────
            let tokenStream = inference.chatStream(
                messages:    messages,
                maxTokens:   req.maxTokens,
                temperature: req.temperature
            )

            let sseStream = AsyncStream<String> { continuation in
                Task.detached(priority: .userInitiated) {
                    let encoder = JSONEncoder()
                    let chunkId = "chatcmpl-\(UUID().uuidString)"

                    func encode(_ chunk: ChatChunk) -> String {
                        (try? encoder.encode(chunk))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    }

                    // First chunk: role
                    let roleChunk = ChatChunk(
                        id: chunkId, object: "chat.completion.chunk", model: modelId,
                        choices: [ChunkChoice(
                            index: 0,
                            delta: ChunkDelta(role: "assistant", content: nil),
                            finishReason: nil
                        )]
                    )
                    continuation.yield(encode(roleChunk))

                    do {
                        for try await token in tokenStream {
                            let chunk = ChatChunk(
                                id: chunkId, object: "chat.completion.chunk", model: modelId,
                                choices: [ChunkChoice(
                                    index: 0,
                                    delta: ChunkDelta(role: nil, content: token),
                                    finishReason: nil
                                )]
                            )
                            continuation.yield(encode(chunk))
                        }
                    } catch {
                        // Error chunk
                        let errChunk = ChatChunk(
                            id: chunkId, object: "chat.completion.chunk", model: modelId,
                            choices: [ChunkChoice(
                                index: 0,
                                delta: ChunkDelta(role: nil, content: nil),
                                finishReason: "error"
                            )]
                        )
                        continuation.yield(encode(errChunk))
                    }

                    // Stop chunk
                    let stopChunk = ChatChunk(
                        id: chunkId, object: "chat.completion.chunk", model: modelId,
                        choices: [ChunkChoice(
                            index: 0,
                            delta: ChunkDelta(role: nil, content: nil),
                            finishReason: "stop"
                        )]
                    )
                    continuation.yield(encode(stopChunk))
                    continuation.finish()
                }
            }

            return HttpResponse.sse(sseStream)

        } else {
            // ── Non-streaming ─────────────────────────────────────────────────
            do {
                let text = try inference.chat(
                    messages:    messages,
                    maxTokens:   req.maxTokens,
                    temperature: req.temperature
                )
                let promptText = req.messages.map { $0.content }.joined(separator: "\n")
                return HttpResponse.json(ChatCompletionResponse(
                    id:      "chatcmpl-\(UUID().uuidString)",
                    object:  "chat.completion",
                    model:   modelId,
                    choices: [ChatChoice(
                        index:        0,
                        message:      ChatMessage(role: "assistant", content: text),
                        finishReason: "stop"
                    )],
                    usage: TokenUsage(prompt: promptText, completion: text)
                ))
            } catch {
                return HttpResponse.error(error.localizedDescription, status: 500)
            }
        }
    }
}

// MARK: - POST /v1/completions

private func registerCompletions(router: Router) {
    router.add("POST", "/v1/completions") { request in
        guard let req = try? request.decode(CompletionRequest.self) else {
            return HttpResponse.error("Invalid JSON body", status: 400)
        }

        let inference = InferenceService.shared
        guard inference.isLoaded else {
            return HttpResponse.error("No model loaded. Call /v1/models/load first.", status: 503)
        }

        // Wrap plain prompt as a user message
        let messages   = [["role": "user", "content": req.prompt]]
        let modelId    = inference.loadedModelId ?? req.model

        if req.stream {
            let tokenStream = inference.chatStream(
                messages:    messages,
                maxTokens:   req.maxTokens,
                temperature: req.temperature
            )

            let sseStream = AsyncStream<String> { continuation in
                Task.detached(priority: .userInitiated) {
                    let encoder  = JSONEncoder()
                    let chunkId  = "cmpl-\(UUID().uuidString)"

                    func encode(_ c: ChatChunk) -> String {
                        (try? encoder.encode(c))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    }

                    do {
                        for try await token in tokenStream {
                            let chunk = ChatChunk(
                                id: chunkId, object: "text_completion", model: modelId,
                                choices: [ChunkChoice(
                                    index: 0,
                                    delta: ChunkDelta(role: nil, content: token),
                                    finishReason: nil
                                )]
                            )
                            continuation.yield(encode(chunk))
                        }
                    } catch {}

                    let stop = ChatChunk(
                        id: chunkId, object: "text_completion", model: modelId,
                        choices: [ChunkChoice(
                            index: 0,
                            delta: ChunkDelta(role: nil, content: nil),
                            finishReason: "stop"
                        )]
                    )
                    continuation.yield(encode(stop))
                    continuation.finish()
                }
            }
            return HttpResponse.sse(sseStream)

        } else {
            do {
                let text = try inference.chat(
                    messages:    messages,
                    maxTokens:   req.maxTokens,
                    temperature: req.temperature
                )
                return HttpResponse.json(CompletionResponse(
                    id:      "cmpl-\(UUID().uuidString)",
                    object:  "text_completion",
                    model:   modelId,
                    choices: [CompletionChoice(text: text, index: 0, finishReason: "stop")],
                    usage:   TokenUsage(prompt: req.prompt, completion: text)
                ))
            } catch {
                return HttpResponse.error(error.localizedDescription, status: 500)
            }
        }
    }
}
