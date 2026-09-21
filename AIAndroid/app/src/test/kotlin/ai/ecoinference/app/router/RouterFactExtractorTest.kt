package ai.ecoinference.app.router

import ai.ecoinference.app.inference.InferenceMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Structural-fact unit tests. Per docs/ROUTING.md §2, structural facts are
 * measurements — right, or a code bug — so ordinary assertions cover them.
 * The *semantic* facts are keyword matching and are evaluated by the corpus
 * (RouterCorpusTest), not here. Mirrors iOS RouterFactExtractorTests.swift.
 */
class RouterFactExtractorTest {

    private fun facts(prompt: String, turns: Int = 0, hasImage: Boolean = false) =
        RouterFactExtractor.extract(
            prompt,
            List(turns) { InferenceMessage(role = "user", text = "turn $it") },
            hasImage,
        )

    private fun int(f: Map<String, FactValue>, key: String) = (f.getValue(key) as FactValue.IntValue).value
    private fun bool(f: Map<String, FactValue>, key: String) = (f.getValue(key) as FactValue.BoolValue).value

    @Test
    fun promptLength_isCharacterCount() {
        assertEquals(11, int(facts("hello world"), "promptLength"))
        assertEquals(0, int(facts(""), "promptLength"))
    }

    @Test
    fun wordCount_ignoresBlankTokens() {
        // Android splits on spaces only, then drops blanks — a tab does not
        // separate words here. If iOS disagrees, that's a parity bug worth
        // knowing about (wordCount is currently unused by any rule).
        assertEquals(3, int(facts("one  two three"), "wordCount"))
        assertEquals(2, int(facts("one\ttwo three"), "wordCount"))
        assertEquals(0, int(facts(""), "wordCount"))
    }

    @Test
    fun conversationTurns_isHistorySize() {
        assertEquals(0, int(facts("hi"), "conversationTurns"))
        assertEquals(7, int(facts("hi", turns = 7), "conversationTurns"))
    }

    @Test
    fun hasImage_isPassedThrough() {
        assertFalse(bool(facts("look"), "hasImage"))
        assertTrue(bool(facts("look", hasImage = true), "hasImage"))
    }

    @Test
    fun hasCodeBlock_detectsTripleBackticks() {
        assertFalse(bool(facts("plain question"), "hasCodeBlock"))
        assertTrue(bool(facts("fix this:\n```kotlin\nval x = 1\n```"), "hasCodeBlock"))
    }

    @Test
    fun hasMathSymbols_detectsOperators() {
        assertFalse(bool(facts("tell me a joke"), "hasMathSymbols"))
        assertTrue(bool(facts("what is 2+2"), "hasMathSymbols"))
        assertTrue(bool(facts("solve x^2 = 4"), "hasMathSymbols"))
    }

    @Test
    fun semanticFacts_matchLiteralKeywordsOnly() {
        // Documents the known weakness (docs/ROUTING.md §1): substring match,
        // case-insensitive on the lowercased prompt, no paraphrase coverage.
        assertTrue(bool(facts("LATEST NEWS about the match"), "mentionsCurrentEvents"))
        assertFalse(bool(facts("who won the game yesterday?"), "mentionsCurrentEvents"))
        assertTrue(bool(facts("can i sue my landlord"), "mentionsSensitiveDomain"))
        assertTrue(bool(facts("please analyze the data"), "requestsDeepReasoning"))
        assertTrue(bool(facts("write a poem about snow"), "requestsCreativeWriting"))
    }
}
