import Foundation

/// Pure scoring math for the Needle-embedder router (docs/ROUTING.md §4).
/// No platform imports beyond Foundation so it compiles into the standalone
/// test target; mirrors Android ExemplarScorer.kt — the two must stay
/// semantically identical (any divergence is a routing bug, see the corpus
/// parity test).
///
/// Pipeline (matches the probe that produced the GO measurement):
///   1. normalize whitespace in every text before embedding,
///   2. center prompt and exemplar vectors by the config's fixed mean
///      (raw needle_embed cosines are anisotropic),
///   3. fact = max cosine vs the category's exemplars > threshold (strict).
enum ExemplarScorer {

    // Character.isWhitespace covers the Unicode White_Space set, matching
    // Kotlin's [\s\p{Z}] regex and, for realistic text, Python's str.split()
    // — the normalization used to bake the shipped config.
    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func center(_ v: [Float], mean: [Float]) -> [Float] {
        precondition(v.count == mean.count, "vector dim \(v.count) != mean dim \(mean.count)")
        return zip(v, mean).map { $0 - $1 }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            let x = Double(a[i]), y = Double(b[i])
            dot += x * y
            na  += x * x
            nb  += y * y
        }
        guard na > 0, nb > 0 else { return 0.0 }   // zero-norm guard
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// - Parameters:
    ///   - promptVec: raw embedding of the (normalized) prompt
    ///   - mean: centering mean from the exemplar config, nil = no centering
    ///   - exemplars: per-category exemplar vectors, ALREADY centered
    ///   - thresholds: per-category strict-greater max-cosine thresholds
    static func semanticFacts(
        promptVec: [Float],
        mean: [Float]?,
        exemplars: [String: [[Float]]],
        thresholds: [String: Double]
    ) -> [String: FactValue] {
        let pv = mean.map { center(promptVec, mean: $0) } ?? promptVec
        var facts: [String: FactValue] = [:]
        for (cat, thr) in thresholds {
            let best = (exemplars[cat] ?? []).map { cosine(pv, $0) }.max() ?? -1.0
            facts[cat] = .bool(best > thr)
        }
        return facts
    }
}
