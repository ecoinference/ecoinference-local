import XCTest

/// Pure-math tests for the Needle-embedder scoring pipeline (docs/ROUTING.md §4).
/// Mirrors Android ExemplarScorerTest.kt — the fixed-vector cases must produce
/// identical facts on both platforms. ExemplarScorer.swift compiles into this
/// standalone target (RouterModels.swift provides FactValue); no engine needed.
final class ExemplarScorerTests: XCTestCase {

    func testNormalize_collapsesWhitespaceRuns() {
        XCTAssertEqual(ExemplarScorer.normalize("  a\t b\n\nc  "), "a b c")
        XCTAssertEqual(ExemplarScorer.normalize("   "), "")
        // Unicode whitespace (non-breaking space) collapses too — matches the
        // Python str.split() normalization used to bake the shipped config
        // and Kotlin's [\s\p{Z}] regex.
        XCTAssertEqual(ExemplarScorer.normalize("a\u{00A0}b"), "a b")
    }

    func testCosine_identicalIsOne_orthogonalIsZero() {
        let v: [Float] = [3, 4]
        XCTAssertEqual(ExemplarScorer.cosine(v, v), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ExemplarScorer.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-9)
        XCTAssertEqual(ExemplarScorer.cosine([0, 0], v), 0.0, accuracy: 1e-9) // zero-norm guard
    }

    func testCenter_subtractsMeanElementwise() {
        XCTAssertEqual(ExemplarScorer.center([1, 2, 3], mean: [1, 1, 1]), [0, 1, 2])
    }

    func testSemanticFacts_strictGreaterThan_perCategoryThresholds() {
        // Prompt along +x; one exemplar aligned, one orthogonal, one absent category.
        let prompt: [Float] = [1, 0]
        let exemplars: [String: [[Float]]] = [
            "aligned": [[2, 0]],   // cosine 1.0
            "ortho":   [[0, 5]],   // cosine 0.0
        ]
        let thresholds: [String: Double] = [
            "aligned": 1.0,    // 1.0 > 1.0 is false — strict
            "ortho":   -0.3,   // 0.0 > -0.3 — the degenerate floor from the sweep
            "absent":  0.5,    // no exemplars: score -1.0 → false
        ]
        let facts = ExemplarScorer.semanticFacts(
            promptVec: prompt, mean: nil, exemplars: exemplars, thresholds: thresholds)
        XCTAssertEqual(facts["aligned"], .bool(false))
        XCTAssertEqual(facts["ortho"], .bool(true))
        XCTAssertEqual(facts["absent"], .bool(false))
    }

    func testCentering_shiftsSimilarity_asItDidInTheProbe() {
        // Two raw vectors with a large shared component look similar; after
        // centering by that shared component they are dissimilar. This is why
        // the config ships a fixed mean (raw needle cosines are anisotropic).
        let mean: [Float] = [10, 0]
        let a: [Float] = [11, 1]
        let b: [Float] = [11, -1]
        XCTAssertGreaterThan(ExemplarScorer.cosine(a, b), 0.9)
        let centered = ExemplarScorer.semanticFacts(
            promptVec: a, mean: mean,
            exemplars: ["cat": [ExemplarScorer.center(b, mean: mean)]],
            thresholds: ["cat": 0.0])
        XCTAssertEqual(centered["cat"], .bool(false))
    }
}
