import Foundation

// MARK: - Health

struct HealthResponse: Codable {
    let status: String
    let modelLoaded: Bool
    let port: Int
    let downloadActive: Bool
    let version: String

    enum CodingKeys: String, CodingKey {
        case status
        case modelLoaded     = "model_loaded"
        case port
        case downloadActive  = "download_active"
        case version
    }
}

// MARK: - Catalog

struct CatalogResponse: Codable {
    let models: [ModelInfo]
}

// MARK: - Model load / unload

struct LoadRequest: Codable {
    let modelId: String
    let useGpu: Bool
    /// KV-cache budget: prompt + history + output combined.
    /// Default 8192 uses the full context window of the Gemma 4 E2B export.
    let maxNumTokens: Int

    enum CodingKeys: String, CodingKey {
        case modelId      = "model_id"
        case useGpu       = "use_gpu"
        case maxNumTokens = "max_num_tokens"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelId      = try c.decode(String.self, forKey: .modelId)
        useGpu       = try c.decodeIfPresent(Bool.self, forKey: .useGpu)       ?? false
        maxNumTokens = try c.decodeIfPresent(Int.self,  forKey: .maxNumTokens) ?? 8192
    }
}

struct LoadResponse: Codable {
    let modelId: String
    let status: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case status
        case error
    }
}

struct UnloadResponse: Codable {
    let status: String
}

// MARK: - Download

struct DownloadRequest: Codable {
    let modelId: String
    let hfToken: String?

    enum CodingKeys: String, CodingKey {
        case modelId  = "model_id"
        case hfToken  = "hf_token"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try c.decode(String.self, forKey: .modelId)
        hfToken = try c.decodeIfPresent(String.self, forKey: .hfToken)
    }
}

/// Sent as SSE events on the download progress stream.
struct DownloadProgressEvent: Codable {
    let modelId: String
    /// 0–100
    let progress: Double
    /// "downloading" | "complete" | "error"
    let status: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case modelId  = "model_id"
        case progress
        case status
        case error
    }

    init(modelId: String, progress: Double = 0, status: String, error: String? = nil) {
        self.modelId  = modelId
        self.progress = progress
        self.status   = status
        self.error    = error
    }
}

// MARK: - Chat completions

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Float
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens  = "max_tokens"
        case temperature
        case stream
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model       = try c.decode(String.self,      forKey: .model)
        messages    = try c.decode([ChatMessage].self, forKey: .messages)
        maxTokens   = try c.decodeIfPresent(Int.self,   forKey: .maxTokens)   ?? 2048
        temperature = try c.decodeIfPresent(Float.self,  forKey: .temperature) ?? 0.8
        stream      = try c.decodeIfPresent(Bool.self,   forKey: .stream)      ?? false
    }
}

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let model: String
    let choices: [ChatChoice]
    let usage: TokenUsage

    enum CodingKeys: String, CodingKey {
        case id, object, model, choices, usage
    }
}

struct ChatChoice: Codable {
    let index: Int
    let message: ChatMessage
    let finishReason: String

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

/// Streaming SSE chunk.
struct ChatChunk: Codable {
    let id: String
    let object: String
    let model: String
    let choices: [ChunkChoice]

    enum CodingKeys: String, CodingKey {
        case id, object, model, choices
    }
}

struct ChunkChoice: Codable {
    let index: Int
    let delta: ChunkDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

struct ChunkDelta: Codable {
    let role: String?
    let content: String?
}

// MARK: - Text completions

struct CompletionRequest: Codable {
    let model: String
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case maxTokens   = "max_tokens"
        case temperature
        case stream
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model       = try c.decode(String.self,  forKey: .model)
        prompt      = try c.decode(String.self,  forKey: .prompt)
        maxTokens   = try c.decodeIfPresent(Int.self,   forKey: .maxTokens)   ?? 2048
        temperature = try c.decodeIfPresent(Float.self,  forKey: .temperature) ?? 0.8
        stream      = try c.decodeIfPresent(Bool.self,   forKey: .stream)      ?? false
    }
}

struct CompletionResponse: Codable {
    let id: String
    let object: String
    let model: String
    let choices: [CompletionChoice]
    let usage: TokenUsage
}

struct CompletionChoice: Codable {
    let text: String
    let index: Int
    let finishReason: String

    enum CodingKeys: String, CodingKey {
        case text
        case index
        case finishReason = "finish_reason"
    }
}

// MARK: - Shared

struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens     = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens      = "total_tokens"
    }
}

struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Helpers

extension TokenUsage {
    /// Rough estimate: ~4 chars per token (Gemma/GPT heuristic).
    init(prompt: String, completion: String) {
        promptTokens     = max(1, prompt.count / 4)
        completionTokens = max(1, completion.count / 4)
        totalTokens      = promptTokens + completionTokens
    }
}
