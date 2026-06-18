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
        "what's happening", "what happened today", "latest news", "current events",
        "this week's", "right now", "breaking news", "as of now", "what's new",
        "in the news", "recent news", "just announced", "happening now",
    ]

    private static let sensitiveDomainKeywords = [
        "legal advice", "lawsuit", "diagnose", "diagnosis", "medication",
        "tax filing", "investment advice", "prescri", "side effects",
        "drug interaction", "is this legal", "am i liable", "can i sue",
        "medical advice", "should i take", "symptoms of", "financial advice",
        "am i at risk", "file a claim",
    ]

    private static let deepReasoningKeywords = [
        "analyze", "analyse", "compare", "pros and cons", "step by step",
        "explain why", "trade-off", "tradeoff", "evaluate", "in depth",
        "debate", "argue", "critique", "which is better", "implications of",
        "break it down", "root cause", "first principles",
    ]

    private static let creativeWritingKeywords = [
        "write a poem", "write a story", "write an essay", "compose a", "write a song",
        "write a blog", "write a letter", "write a cover letter", "write a speech",
        "draft a", "write an article", "write a script",
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
