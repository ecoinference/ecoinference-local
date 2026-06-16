import Foundation

/// Turns a prompt + conversation context into the fact dictionary the rule
/// engine evaluates against. Keyword lists are intentionally simple — this is
/// the part most likely to be tuned over time as we see real routing misses.
enum RouterFactExtractor {

    static func extract(prompt: String, history: [InferenceMessage], hasImage: Bool) -> [String: FactValue] {
        let lower = prompt.lowercased()
        return [
            "promptLength":            .int(prompt.count),
            "wordCount":               .int(prompt.split(separator: " ").count),
            "conversationTurns":       .int(history.count),
            "hasImage":                .bool(hasImage),
            "hasCodeBlock":            .bool(prompt.contains("```")),
            "hasMathSymbols":          .bool(containsMathSymbols(lower)),
            "mentionsCurrentEvents":   .bool(containsAny(lower, currentEventsKeywords)),
            "mentionsSensitiveDomain": .bool(containsAny(lower, sensitiveDomainKeywords)),
            "requestsDeepReasoning":   .bool(containsAny(lower, deepReasoningKeywords)),
            "requestsCreativeWriting": .bool(containsAny(lower, creativeWritingKeywords)),
        ]
    }

    // MARK: - Keyword lists (tune here)

    private static let currentEventsKeywords = [
        "today", "latest", "current", "this week", "right now", "recently",
        "breaking news", "as of now"
    ]

    private static let sensitiveDomainKeywords = [
        "legal advice", "lawsuit", "diagnose", "diagnosis", "medication",
        "tax filing", "investment advice", "prescri"
    ]

    private static let deepReasoningKeywords = [
        "analyze", "analyse", "compare", "pros and cons", "step by step",
        "explain why", "trade-off", "tradeoff", "evaluate", "in depth"
    ]

    private static let creativeWritingKeywords = [
        "write a poem", "write a story", "write an essay", "compose a", "write a song"
    ]

    // MARK: - Helpers

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func containsMathSymbols(_ text: String) -> Bool {
        let symbols = CharacterSet(charactersIn: "+-*/=^√∫∑")
        return text.rangeOfCharacter(from: symbols) != nil
    }
}
