import Foundation

/// Calls Google's Gemini API — the cloud tier of the LLM router.
/// Takes the same `InferenceMessage` shape as `InferenceService` so call
/// sites (and eventually `RouterService`) can swap local/cloud without
/// reshaping the conversation.
final class GeminiService {

    static let shared = GeminiService()
    private init() {}

    /// "latest" alias so we don't need to track Google's dot-version bumps.
    static let defaultModel = "gemini-flash-latest"

    private let session = URLSession.shared

    enum GeminiServiceError: LocalizedError {
        case missingApiKey
        case httpError(Int, String)
        case emptyResponse
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return "No Gemini API key set. Add one in Settings → Cloud AI."
            case .httpError(let code, let body):
                return "Gemini API error \(code): \(body)"
            case .emptyResponse:
                return "Gemini returned an empty response."
            case .decodingError(let msg):
                return "Failed to decode Gemini response: \(msg)"
            }
        }
    }

    /// Non-streaming chat completion against Gemini.
    func chat(
        messages:     [InferenceMessage],
        systemPrompt: String? = nil,
        model:        String = GeminiService.defaultModel,
        maxTokens:    Int    = 2048,
        temperature:  Float  = 0.8
    ) async throws -> String {
        let apiKey = SettingsService.shared.geminiApiKey
        guard !apiKey.isEmpty else { throw GeminiServiceError.missingApiKey }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Header (not query string) keeps the key out of URLs/logs.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiRequest(
            contents: messages.map(GeminiContent.init),
            systemInstruction: systemPrompt.map { GeminiSystemInstruction(parts: [GeminiPart(text: $0)]) },
            generationConfig: GeminiGenerationConfig(temperature: temperature, maxOutputTokens: maxTokens)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiServiceError.httpError(0, "no HTTP response")
        }
        guard http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw GeminiServiceError.httpError(http.statusCode, bodyStr)
        }

        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw GeminiServiceError.decodingError(error.localizedDescription)
        }

        guard let text = decoded.candidates?.first?.content?.parts?.first?.text else {
            throw GeminiServiceError.emptyResponse
        }
        return text
    }
}

// MARK: - Request models

private struct GeminiRequest: Encodable {
    let contents:           [GeminiContent]
    let systemInstruction:  GeminiSystemInstruction?
    let generationConfig:   GeminiGenerationConfig
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiGenerationConfig: Encodable {
    let temperature:     Float
    let maxOutputTokens: Int
}

private struct GeminiContent: Encodable {
    let role:  String
    let parts: [GeminiPart]

    init(_ message: InferenceMessage) {
        // Gemini uses "model" for assistant turns, "user" for everything else.
        role = message.role == "assistant" ? "model" : "user"

        var parts: [GeminiPart] = []
        if !message.text.isEmpty {
            parts.append(GeminiPart(text: message.text))
        }
        if let imageData = message.imageData {
            parts.append(GeminiPart(inlineData: GeminiInlineData(
                mimeType: "image/jpeg",
                data: imageData.base64EncodedString()
            )))
        }
        self.parts = parts
    }
}

/// Exactly one of `text` / `inlineData` is set per part — custom encode(to:)
/// keeps the unused one out of the JSON body entirely (rather than `null`).
private struct GeminiPart: Encodable {
    var text:       String?
    var inlineData: GeminiInlineData?

    init(text: String)               { self.text = text }
    init(inlineData: GeminiInlineData) { self.inlineData = inlineData }

    enum CodingKeys: String, CodingKey { case text, inlineData }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(inlineData, forKey: .inlineData)
    }
}

private struct GeminiInlineData: Encodable {
    let mimeType: String
    let data:     String
}

// MARK: - Response models

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Decodable {
    let content:      GeminiResponseContent?
    let finishReason: String?
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]?
    let role:  String?
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}
