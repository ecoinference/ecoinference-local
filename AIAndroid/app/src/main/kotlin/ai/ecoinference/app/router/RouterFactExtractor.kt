package ai.ecoinference.app.router

import ai.ecoinference.app.inference.InferenceMessage

/**
 * Turns a prompt + conversation context into the fact map the rule engine
 * evaluates against. Mirrors iOS RouterFactExtractor.swift — keep keyword
 * lists in sync between platforms.
 */
object RouterFactExtractor {

    fun extract(
        prompt: String,
        history: List<InferenceMessage> = emptyList(),
        hasImage: Boolean = false,
    ): MutableMap<String, FactValue> {
        val lower = prompt.lowercase()
        return mutableMapOf(
            "promptLength"            to FactValue.IntValue(prompt.length),
            "wordCount"               to FactValue.IntValue(prompt.split(" ").count { it.isNotBlank() }),
            "conversationTurns"       to FactValue.IntValue(history.size),
            "hasImage"                to FactValue.BoolValue(hasImage),
            "hasCodeBlock"            to FactValue.BoolValue(prompt.contains("```")),
            "hasMathSymbols"          to FactValue.BoolValue(containsMathSymbols(lower)),
            "mentionsCurrentEvents"   to FactValue.BoolValue(containsAny(lower, currentEventsKeywords)),
            "mentionsSensitiveDomain" to FactValue.BoolValue(containsAny(lower, sensitiveDomainKeywords)),
            "requestsDeepReasoning"   to FactValue.BoolValue(containsAny(lower, deepReasoningKeywords)),
            "requestsCreativeWriting" to FactValue.BoolValue(containsAny(lower, creativeWritingKeywords)),
        )
    }

    // ── Keyword lists (tune here — keep in sync with iOS) ───────────────────

    private val currentEventsKeywords = listOf(
        "what's happening", "what happened today", "latest news", "current events",
        "this week's", "right now", "breaking news", "as of now", "what's new",
        "in the news", "recent news", "just announced", "happening now",
    )

    private val sensitiveDomainKeywords = listOf(
        "legal advice", "lawsuit", "diagnose", "diagnosis", "medication",
        "tax filing", "investment advice", "prescri", "side effects",
        "drug interaction", "is this legal", "am i liable", "can i sue",
        "medical advice", "should i take", "symptoms of", "financial advice",
        "am i at risk", "file a claim",
    )

    private val deepReasoningKeywords = listOf(
        "analyze", "analyse", "compare", "pros and cons", "step by step",
        "explain why", "trade-off", "tradeoff", "evaluate", "in depth",
        "debate", "argue", "critique", "which is better", "implications of",
        "break it down", "root cause", "first principles",
    )

    private val creativeWritingKeywords = listOf(
        "write a poem", "write a story", "write an essay", "compose a", "write a song",
        "write a blog", "write a letter", "write a cover letter", "write a speech",
        "draft a", "write an article", "write a script",
    )

    // ── Helpers ───────────────────────────────────────────────────────────

    private fun containsAny(text: String, keywords: List<String>) = keywords.any { text.contains(it) }

    private fun containsMathSymbols(text: String) = text.any { it in "+-*/=^√∫∑" }
}
