package ai.ecoinference.app.router

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-math tests for the Needle-embedder scoring pipeline (docs/ROUTING.md §4).
 * Mirrors iOS ExemplarScorerTests.swift — the fixed-vector cases must produce
 * identical facts on both platforms.
 */
class ExemplarScorerTest {

    @Test
    fun `normalize collapses whitespace runs`() {
        assertEquals("a b c", ExemplarScorer.normalize("  a\t b\n\nc  "))
        assertEquals("", ExemplarScorer.normalize("   "))
        // Unicode whitespace (non-breaking space) collapses too — matches the
        // Python str.split() normalization used to bake the shipped config.
        assertEquals("a b", ExemplarScorer.normalize("a\u00A0b"))
    }

    @Test
    fun `cosine of identical vectors is 1, orthogonal is 0`() {
        val v = floatArrayOf(3f, 4f)
        assertEquals(1.0, ExemplarScorer.cosine(v, v), 1e-9)
        assertEquals(0.0, ExemplarScorer.cosine(floatArrayOf(1f, 0f), floatArrayOf(0f, 1f)), 1e-9)
        assertEquals(0.0, ExemplarScorer.cosine(floatArrayOf(0f, 0f), v), 1e-9) // zero-norm guard
    }

    @Test
    fun `center subtracts the mean elementwise`() {
        val out = ExemplarScorer.center(floatArrayOf(1f, 2f, 3f), floatArrayOf(1f, 1f, 1f))
        assertArrayEquals(floatArrayOf(0f, 1f, 2f), out)
    }

    @Test
    fun `semanticFacts uses strict greater-than against per-category thresholds`() {
        // Prompt along +x; one exemplar aligned, one orthogonal, one absent category.
        val prompt = floatArrayOf(1f, 0f)
        val exemplars = mapOf(
            "aligned" to listOf(floatArrayOf(2f, 0f)),   // cosine 1.0
            "ortho"   to listOf(floatArrayOf(0f, 5f)),   // cosine 0.0
        )
        val thresholds = mapOf(
            "aligned" to 1.0,   // 1.0 > 1.0 is false — strict
            "ortho"   to -0.3,  // 0.0 > -0.3 — the degenerate floor from the sweep
            "absent"  to 0.5,   // no exemplars: score -1.0 → false
        )
        val facts = ExemplarScorer.semanticFacts(prompt, mean = null, exemplars = exemplars, thresholds = thresholds)
        assertEquals(FactValue.BoolValue(false), facts["aligned"])
        assertEquals(FactValue.BoolValue(true), facts["ortho"])
        assertEquals(FactValue.BoolValue(false), facts["absent"])
    }

    @Test
    fun `centering shifts similarity as it did in the probe`() {
        // Two raw vectors with a large shared component look similar; after
        // centering by that shared component they are dissimilar. This is why
        // the config ships a fixed mean (raw needle cosines are anisotropic).
        val mean = floatArrayOf(10f, 0f)
        val a = floatArrayOf(11f, 1f)
        val b = floatArrayOf(11f, -1f)
        assertTrue(ExemplarScorer.cosine(a, b) > 0.9)
        val centered = ExemplarScorer.semanticFacts(
            promptVec = a, mean = mean,
            exemplars = mapOf("cat" to listOf(ExemplarScorer.center(b, mean))),
            thresholds = mapOf("cat" to 0.0),
        )
        assertFalse((centered["cat"] as FactValue.BoolValue).value)
    }

    private fun assertArrayEquals(expected: FloatArray, actual: FloatArray) {
        assertEquals(expected.toList(), actual.toList())
    }
}
