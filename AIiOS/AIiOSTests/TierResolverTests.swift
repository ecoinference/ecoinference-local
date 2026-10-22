import XCTest

/// TierResolver against the shared fixtures at tests/router/resolver_cases.json —
/// the same file Android's TierResolverTest.kt reads, so any iOS/Android
/// disagreement in resolution OR reason strings fails one of the two suites.
/// Also guards the rules-v3 vocabulary and the byte-identity of the bundled
/// default_router_rules_v3.json across platforms. TierResolver.swift and
/// RouterModels.swift compile directly into this standalone target.
final class TierResolverTests: XCTestCase {

    // MARK: - Fixture schema

    private struct FixtureTierState: Decodable {
        let configured: Bool
        let reachable: Reachability
        let vision: Bool
        let web: Bool
        let contextLimit: Int
    }

    private struct FixturePolicy: Decodable {
        let ceiling: String
        let pin: String?
        let offerAllCloud: Bool
    }

    private struct FixtureExpect: Decodable {
        let action: String
        let tier: String
        let reason: String
        let fallbackTier: String?
        let fallbackReason: String?
    }

    private struct FixtureCase: Decodable {
        let id: String
        let minTier: String
        let ruleReason: String
        let facts: [String: FactValue]
        let tiers: [String: FixtureTierState]
        let policy: FixturePolicy
        let expect: FixtureExpect
    }

    private struct FixtureFile: Decodable {
        let cases: [FixtureCase]
    }

    // MARK: - Loading (same #filePath resolution as RouterCorpusTests)

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AIiOSTests/
            .deletingLastPathComponent()   // AIiOS/
            .deletingLastPathComponent()   // repo root
    }

    private func loadCases() throws -> [FixtureCase] {
        let url = repoRoot.appendingPathComponent("tests/router/resolver_cases.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureFile.self, from: data).cases
    }

    private func tier(_ decision: String) throws -> Tier {
        guard let t = Tier(decision: decision) else {
            XCTFail("bad tier decision: \(decision)")
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "bad tier decision: \(decision)"))
        }
        return t
    }

    // MARK: - Tests

    func testResolverCases_matchSharedFixtures() throws {
        for fixture in try loadCases() {
            var tiers: [Tier: TierState] = [:]
            for (key, fx) in fixture.tiers {
                tiers[try tier(key)] = TierState(
                    configured: fx.configured, reachable: fx.reachable,
                    vision: fx.vision, web: fx.web, contextLimit: fx.contextLimit)
            }
            let policy = ResolverPolicy(
                ceiling: try tier(fixture.policy.ceiling),
                pin: try fixture.policy.pin.map { try tier($0) },
                offerAllCloud: fixture.policy.offerAllCloud)
            let result = TierResolver.resolve(
                minTier: try tier(fixture.minTier),
                ruleReason: fixture.ruleReason,
                facts: fixture.facts,
                tiers: tiers,
                policy: policy)

            XCTAssertEqual(result.action.rawValue, fixture.expect.action, "\(fixture.id): action")
            XCTAssertEqual(result.tier, try tier(fixture.expect.tier), "\(fixture.id): tier")
            XCTAssertEqual(result.reason, fixture.expect.reason, "\(fixture.id): reason")
            XCTAssertEqual(result.fallbackTier, try fixture.expect.fallbackTier.map { try tier($0) },
                           "\(fixture.id): fallbackTier")
            XCTAssertEqual(result.fallbackReason, fixture.expect.fallbackReason,
                           "\(fixture.id): fallbackReason")
        }
    }

    func testRulesV3_useOnlyTierVocabulary() throws {
        let url = repoRoot.appendingPathComponent("AIiOS/AIiOS/default_router_rules_v3.json")
        let ruleSet = try JSONDecoder().decode(RouterRuleSet.self, from: try Data(contentsOf: url))
        XCTAssertEqual(ruleSet.version, 3)
        XCTAssertEqual(Tier(decision: ruleSet.defaultDecision), .onDevice)
        for rule in ruleSet.rules {
            XCTAssertNotNil(Tier(decision: rule.decision), "\(rule.id): decision not in v3 vocabulary")
        }
        // §3.3: the vision capability check moved out of the rules file.
        XCTAssertFalse(ruleSet.rules.contains { $0.id == "image_unsupported_locally" })
        // D3: sensitive stays on user-owned hardware, never minTier cloud.
        let sensitive = try XCTUnwrap(ruleSet.rules.first { $0.id == "sensitive_domain" })
        XCTAssertEqual(Tier(decision: sensitive.decision), .selfHosted)
    }

    func testRulesV3_byteIdenticalAcrossPlatforms() throws {
        let ios = try Data(contentsOf:
            repoRoot.appendingPathComponent("AIiOS/AIiOS/default_router_rules_v3.json"))
        let android = try Data(contentsOf:
            repoRoot.appendingPathComponent("AIAndroid/app/src/main/assets/default_router_rules_v3.json"))
        XCTAssertEqual(ios, android, "default_router_rules_v3.json diverged between platforms")
    }
}
