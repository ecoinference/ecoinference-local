import XCTest
// No `@testable import` — RuleEngine.swift, RouterFactExtractor.swift and
// RouterModels.swift are compiled directly into this standalone test bundle
// (same pattern as AgentLoopTests). Mirrors Android's RouterCorpusTest.kt;
// both read the *same* corpus at tests/router/corpus.jsonl.
// Design and rationale: docs/ROUTING.md §2.

final class RouterCorpusTests: XCTestCase {

    // MARK: - Corpus schema (must stay in sync with the JSONL and Android)

    private struct CaseContext: Decodable {
        let turns: Int
        let hasImage: Bool
        let localSupportsImage: Bool

        private enum CodingKeys: String, CodingKey {
            case turns, hasImage, localSupportsImage
        }

        init() {
            turns = 0
            hasImage = false
            localSupportsImage = true
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            turns = try c.decodeIfPresent(Int.self, forKey: .turns) ?? 0
            hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
            localSupportsImage = try c.decodeIfPresent(Bool.self, forKey: .localSupportsImage) ?? true
        }
    }

    private struct PolicySpec: Decodable {
        let ceiling: String?
        let pin: String?
        let offerAllCloud: Bool?
    }

    private struct CorpusCase: Decodable {
        let id: String
        let prompt: String
        let expect: String
        let because: String
        let context: CaseContext
        let notes: String
        let knownMiss: Bool
        // ── Three-tier fields (docs/ROUTING_THREE_TIER.md §6) ──
        let expectMinTier: String
        let expectTier: String
        let expectAction: String
        let expectFallbackTier: String?
        /// Per-tier availability shorthand: ok | down | absent | no_web | no_vision.
        let availability: [String: String]
        let policy: PolicySpec?

        private enum CodingKeys: String, CodingKey {
            case id, prompt, expect, because, context, notes
            case knownMiss = "known_miss"
            case expectMinTier = "expect_min_tier"
            case expectTier = "expect_tier"
            case expectAction = "expect_action"
            case expectFallbackTier = "expect_fallback_tier"
            case availability, policy
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            prompt = try c.decode(String.self, forKey: .prompt)
            expect = try c.decode(String.self, forKey: .expect)
            because = try c.decodeIfPresent(String.self, forKey: .because) ?? ""
            context = try c.decodeIfPresent(CaseContext.self, forKey: .context) ?? CaseContext()
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            knownMiss = try c.decodeIfPresent(Bool.self, forKey: .knownMiss) ?? false
            expectMinTier = try c.decodeIfPresent(String.self, forKey: .expectMinTier) ?? ""
            expectTier = try c.decodeIfPresent(String.self, forKey: .expectTier) ?? ""
            expectAction = try c.decodeIfPresent(String.self, forKey: .expectAction) ?? "send"
            expectFallbackTier = try c.decodeIfPresent(String.self, forKey: .expectFallbackTier)
            availability = try c.decodeIfPresent([String: String].self, forKey: .availability) ?? [:]
            policy = try c.decodeIfPresent(PolicySpec.self, forKey: .policy)
        }
    }

    // MARK: - Loading

    /// Repo root, resolved from this file's location so the test reads the same
    /// shared corpus and rules regardless of simulator/runner working directory.
    /// Simulators share the Mac filesystem, so #filePath resolution works.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AIiOSTests/
            .deletingLastPathComponent()   // AIiOS/
            .deletingLastPathComponent()   // repo root
    }

    private func loadCases() throws -> [CorpusCase] {
        let url = repoRoot.appendingPathComponent("tests/router/corpus.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(CorpusCase.self, from: Data($0.utf8)) }
    }

    private func loadRuleSet() throws -> RouterRuleSet {
        let url = repoRoot.appendingPathComponent("AIiOS/AIiOS/default_router_rules.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RouterRuleSet.self, from: data)
    }

    /// Mirrors RouterService.decide() minus Firebase: same facts, same engine.
    private func decide(_ c: CorpusCase, ruleSet: RouterRuleSet) -> RuleEngine.Outcome {
        let history = (0..<c.context.turns).map { InferenceMessage(role: "user", text: "turn \($0)") }
        var facts = RouterFactExtractor.extract(prompt: c.prompt, history: history, hasImage: c.context.hasImage)
        facts["localSupportsImage"] = .bool(c.context.localSupportsImage)
        return RuleEngine().decide(facts: facts, ruleSet: ruleSet)
    }

    private func allDecisions() throws -> [String: String] {
        let ruleSet = try loadRuleSet()
        return try loadCases().reduce(into: [String: String]()) { result, c in
            result[c.id] = decide(c, ruleSet: ruleSet).decision
        }
    }

    // MARK: - Tests

    func testCorpusCases_withoutKnownMiss_routeAsExpected() throws {
        let ruleSet = try loadRuleSet()
        for c in try loadCases() where !c.knownMiss {
            let outcome = decide(c, ruleSet: ruleSet)
            XCTAssertEqual(
                outcome.decision, c.expect,
                "\(c.id): rule=\(outcome.ruleId ?? "default") — \(c.because)"
            )
        }
    }

    /// Reports the four metrics from docs/ROUTING.md §2 and dumps this
    /// platform's decisions. Never fails — known_miss cases are *expected* to
    /// be wrong until a semantic-fact replacement lands; the conversion count
    /// is the instrument that decides whether one earns its cost.
    func testCorpusMetrics_reportAndDumpDecisions() throws {
        let ruleSet = try loadRuleSet()
        let cases = try loadCases()
        let decisions = try allDecisions()

        let labeled = cases.filter { !$0.knownMiss }
        let misses = cases.filter { $0.knownMiss }
        let falseLocal = labeled.filter { $0.expect == "cloud" && decisions[$0.id] == "local" }
        let falseCloud = labeled.filter { $0.expect == "local" && decisions[$0.id] == "cloud" }
        let retainedLocal = labeled.filter { decisions[$0.id] == "local" }
        let converted = misses.filter { decisions[$0.id] == $0.expect }

        print("── router corpus metrics (ios) ──────────────────────────────")
        print("cases: \(cases.count) (labeled \(labeled.count), known_miss \(misses.count))")
        print("local retention (labeled): \(retainedLocal.count)/\(labeled.count)")
        print("false local : \(falseLocal.count) \(falseLocal.map(\.id))")
        print("false cloud : \(falseCloud.count) \(falseCloud.map(\.id))")
        print("known_miss converted: \(converted.count)/\(misses.count) \(converted.map(\.id))")
        print("─────────────────────────────────────────────────────────────")

        let dump = decisions.keys.sorted().map { "\($0) \(decisions[$0]!)" }.joined(separator: "\n") + "\n"
        try dump.write(to: repoRoot.appendingPathComponent("tests/router/decisions-ios.txt"),
                       atomically: true, encoding: .utf8)
    }

    /// Any iOS/Android disagreement is always a bug — this converts the
    /// "keep in sync" comment into something mechanically enforced. Compares
    /// against Android's dumped decisions; skipped until the Android corpus
    /// test has been run at least once.
    func testCrossPlatformDecisions_agreeWithAndroidDump() throws {
        let androidURL = repoRoot.appendingPathComponent("tests/router/decisions-android.txt")
        guard FileManager.default.fileExists(atPath: androidURL.path) else {
            throw XCTSkip("Run the Android corpus tests first (missing decisions-android.txt)")
        }
        let android = try String(contentsOf: androidURL, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: " ")
                guard parts.count == 2 else { return }
                result[String(parts[0])] = String(parts[1])
            }
        XCTAssertEqual(try allDecisions(), android, "iOS/Android routing divergence (always a bug)")
    }

    // MARK: - Three-tier pipeline: rules v3 → minTier → TierResolver
    // docs/ROUTING_THREE_TIER.md §6. Same standard profile and availability
    // shorthand on both platforms — the v3 parity dump enforces it.

    private struct V3Outcome {
        let minTier: Tier
        let ruleId: String?
        let result: ResolverResult
    }

    private func loadRuleSetV3() throws -> RouterRuleSet {
        let url = repoRoot.appendingPathComponent("AIiOS/AIiOS/default_router_rules_v3.json")
        return try JSONDecoder().decode(RouterRuleSet.self, from: try Data(contentsOf: url))
    }

    /// Standard capability profile; on-device vision comes from the case's
    /// localSupportsImage (that fact IS the on-device tier's vision capability
    /// under v3 — the image rule moved into the resolver, §3.3).
    private func tiersFor(_ c: CorpusCase) -> [Tier: TierState] {
        func state(_ tier: Tier) -> TierState {
            var configured = true
            var reachable: Reachability = .yes
            var vision = tier == .onDevice ? c.context.localSupportsImage : true
            var web = tier != .onDevice
            var contextLimit = 1_000_000
            switch tier {
            case .onDevice:   contextLimit = 2_000
            case .selfHosted: contextLimit = 32_000
            case .cloud:      contextLimit = 1_000_000
            }
            switch c.availability[tier.decision] ?? "ok" {
            case "ok":        break
            case "down":      reachable = .no
            case "absent":    configured = false
            case "no_web":    web = false
            case "no_vision": vision = false
            default:
                preconditionFailure("\(c.id): unknown availability shorthand \(c.availability[tier.decision]!)")
            }
            return TierState(configured: configured, reachable: reachable,
                             vision: vision, web: web, contextLimit: contextLimit)
        }
        return Dictionary(uniqueKeysWithValues: Tier.allCases.map { ($0, state($0)) })
    }

    private func parseTier(_ decision: String?, _ c: CorpusCase, _ what: String) throws -> Tier? {
        guard let decision else { return nil }
        guard let t = Tier(decision: decision) else {
            XCTFail("\(c.id): bad \(what) tier '\(decision)'")
            throw NSError(domain: "RouterCorpusTests", code: 1)
        }
        return t
    }

    private func policyFor(_ c: CorpusCase) throws -> ResolverPolicy {
        guard let p = c.policy else { return ResolverPolicy() }
        return ResolverPolicy(
            ceiling: try parseTier(p.ceiling, c, "ceiling") ?? .cloud,
            pin: try parseTier(p.pin, c, "pin"),
            offerAllCloud: p.offerAllCloud ?? false)
    }

    private func factsFor(_ c: CorpusCase) -> [String: FactValue] {
        let history = (0..<c.context.turns).map { InferenceMessage(role: "user", text: "turn \($0)") }
        var facts = RouterFactExtractor.extract(prompt: c.prompt, history: history, hasImage: c.context.hasImage)
        facts["localSupportsImage"] = .bool(c.context.localSupportsImage)
        return facts
    }

    private func runV3(_ c: CorpusCase, ruleSet: RouterRuleSet) throws -> V3Outcome {
        let facts = factsFor(c)
        let outcome = RuleEngine().decide(facts: facts, ruleSet: ruleSet)
        guard let minTier = Tier(decision: outcome.decision) else {
            XCTFail("\(c.id): v3 rules produced non-tier decision '\(outcome.decision)'")
            throw NSError(domain: "RouterCorpusTests", code: 2)
        }
        let result = TierResolver.resolve(minTier: minTier, ruleReason: outcome.reason,
                                          facts: facts, tiers: tiersFor(c), policy: try policyFor(c))
        return V3Outcome(minTier: minTier, ruleId: outcome.ruleId, result: result)
    }

    /// Dump line: "id minTier action tier fallback" — fallback is "-" for sends.
    private func v3Line(_ id: String, _ o: V3Outcome) -> String {
        "\(id) \(o.minTier.decision) \(o.result.action.rawValue) \(o.result.tier.decision) " +
            (o.result.fallbackTier?.decision ?? "-")
    }

    private func v3Matches(_ o: V3Outcome, _ c: CorpusCase) -> Bool {
        o.minTier.decision == c.expectMinTier &&
            o.result.action.rawValue == c.expectAction &&
            o.result.tier.decision == c.expectTier &&
            o.result.fallbackTier?.decision == c.expectFallbackTier
    }

    func testV3CorpusCases_withoutKnownMiss_routeAsExpected() throws {
        let ruleSet = try loadRuleSetV3()
        for c in try loadCases() where !c.knownMiss {
            let o = try runV3(c, ruleSet: ruleSet)
            XCTAssertTrue(v3Matches(o, c),
                "\(c.id): expected (\(c.expectMinTier), \(c.expectAction), \(c.expectTier), " +
                "\(c.expectFallbackTier ?? "-")), got (\(o.minTier.decision), \(o.result.action.rawValue), " +
                "\(o.result.tier.decision), \(o.result.fallbackTier?.decision ?? "-")) " +
                "(rule=\(o.ruleId ?? "default")) — \(c.because)")
        }
    }

    func testV3CorpusMetrics_reportAndDumpDecisions() throws {
        let ruleSet = try loadRuleSetV3()
        let cases = try loadCases()
        var outcomes: [String: V3Outcome] = [:]
        for c in cases { outcomes[c.id] = try runV3(c, ruleSet: ruleSet) }

        let labeled = cases.filter { !$0.knownMiss }
        let misses = cases.filter { $0.knownMiss }
        let labeledPass = labeled.filter { v3Matches(outcomes[$0.id]!, $0) }
        let converted = misses.filter { v3Matches(outcomes[$0.id]!, $0) }
        let sends = outcomes.values.filter { $0.result.action == .send }.count
        let cloudSends = outcomes.values.filter { $0.result.action == .send && $0.result.tier == .cloud }.count
        let offers = outcomes.values.filter { $0.result.action == .offer }.count

        print("── three-tier corpus metrics (ios) ──────────────────────────")
        print("cases: \(cases.count) (labeled \(labeled.count), known_miss \(misses.count))")
        print("labeled passing (minTier,action,tier,fallback): \(labeledPass.count)/\(labeled.count)")
        print("known_miss converted: \(converted.count)/\(misses.count) \(converted.map(\.id))")
        print("datacenter avoidance: sends \(sends) (cloud \(cloudSends)), offers \(offers) " +
              "(keyword facts only — embedder unavailable in test target)")
        print("─────────────────────────────────────────────────────────────")

        let dump = outcomes.keys.sorted().map { v3Line($0, outcomes[$0]!) }.joined(separator: "\n") + "\n"
        try dump.write(to: repoRoot.appendingPathComponent("tests/router/decisions-v3-ios.txt"),
                       atomically: true, encoding: .utf8)
    }

    func testV3CrossPlatformDecisions_agreeWithAndroidDump() throws {
        let androidURL = repoRoot.appendingPathComponent("tests/router/decisions-v3-android.txt")
        guard FileManager.default.fileExists(atPath: androidURL.path) else {
            throw XCTSkip("Run the Android corpus tests first (missing decisions-v3-android.txt)")
        }
        let android = try String(contentsOf: androidURL, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .reduce(into: [String: [String]]()) { result, line in
                let parts = line.split(separator: " ").map(String.init)
                guard parts.count == 5 else { return }
                result[parts[0]] = Array(parts[1...])
            }
        let ruleSet = try loadRuleSetV3()
        var ios: [String: [String]] = [:]
        for c in try loadCases() {
            let parts = v3Line(c.id, try runV3(c, ruleSet: ruleSet)).split(separator: " ").map(String.init)
            ios[parts[0]] = Array(parts[1...])
        }
        XCTAssertEqual(ios, android, "iOS/Android three-tier divergence (always a bug)")
    }
}
