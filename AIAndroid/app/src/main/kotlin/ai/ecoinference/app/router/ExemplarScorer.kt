package ai.ecoinference.app.router

import kotlin.math.sqrt

/**
 * Pure scoring math for the Needle-embedder router (docs/ROUTING.md §4).
 * No platform imports so it runs on the plain JVM test runner; mirrors iOS
 * ExemplarScorer.swift — the two must stay semantically identical (any
 * divergence is a routing bug, see the corpus parity test).
 *
 * Pipeline (matches the probe that produced the GO measurement):
 *   1. normalize whitespace in every text before embedding,
 *   2. center prompt and exemplar vectors by the config's fixed mean
 *      (raw needle_embed cosines are anisotropic),
 *   3. fact = max cosine vs the category's exemplars > threshold (strict).
 */
object ExemplarScorer {

    // [\s\p{Z}] matches the Unicode White_Space set Swift's
    // Character.isWhitespace uses (\p{Z} covers NBSP and friends, which
    // Java's Char.isWhitespace() excludes) and, for realistic text, Python's
    // str.split() — the normalization used to bake the shipped config.
    private val whitespaceRun = Regex("[\\s\\p{Z}]+")

    fun normalize(text: String): String =
        text.split(whitespaceRun).filter { it.isNotEmpty() }.joinToString(" ")

    fun center(v: FloatArray, mean: FloatArray): FloatArray {
        require(v.size == mean.size) { "vector dim ${v.size} != mean dim ${mean.size}" }
        return FloatArray(v.size) { v[it] - mean[it] }
    }

    fun cosine(a: FloatArray, b: FloatArray): Double {
        var dot = 0.0; var na = 0.0; var nb = 0.0
        for (i in a.indices) {
            dot += a[i].toDouble() * b[i]
            na  += a[i].toDouble() * a[i]
            nb  += b[i].toDouble() * b[i]
        }
        return if (na > 0 && nb > 0) dot / (sqrt(na) * sqrt(nb)) else 0.0
    }

    /**
     * @param promptVec  raw embedding of the (normalized) prompt
     * @param mean       centering mean from the exemplar config, null = no centering
     * @param exemplars  per-category exemplar vectors, ALREADY centered
     * @param thresholds per-category strict-greater thresholds
     */
    fun semanticFacts(
        promptVec: FloatArray,
        mean: FloatArray?,
        exemplars: Map<String, List<FloatArray>>,
        thresholds: Map<String, Double>,
    ): Map<String, FactValue> {
        val pv = if (mean != null) center(promptVec, mean) else promptVec
        return thresholds.mapValues { (cat, thr) ->
            val best = exemplars[cat].orEmpty()
                .maxOfOrNull { cosine(pv, it) } ?: -1.0
            FactValue.BoolValue(best > thr)
        }
    }
}
