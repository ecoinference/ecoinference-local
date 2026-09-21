import XCTest
// Structural-fact unit tests — mirrors Android's RouterFactExtractorTest.kt,
// same assertions on both platforms. Per docs/ROUTING.md §2, structural facts
// are measurements (right, or a code bug), so ordinary assertions cover them;
// the *semantic* facts are evaluated by the corpus (RouterCorpusTests).

final class RouterFactExtractorTests: XCTestCase {

    private func facts(_ prompt: String, turns: Int = 0, hasImage: Bool = false) -> [String: FactValue] {
        RouterFactExtractor.extract(
            prompt: prompt,
            history: (0..<turns).map { InferenceMessage(role: "user", text: "turn \($0)") },
            hasImage: hasImage
        )
    }

    private func intValue(_ f: [String: FactValue], _ key: String) -> Int {
        guard case .int(let v)? = f[key] else {
            XCTFail("\(key) is not an int fact")
            return -1
        }
        return v
    }

    private func boolValue(_ f: [String: FactValue], _ key: String) -> Bool {
        guard case .bool(let v)? = f[key] else {
            XCTFail("\(key) is not a bool fact")
            return false
        }
        return v
    }

    func testPromptLength_isCharacterCount() {
        XCTAssertEqual(intValue(facts("hello world"), "promptLength"), 11)
        XCTAssertEqual(intValue(facts(""), "promptLength"), 0)
    }

    func testWordCount_ignoresBlankTokens() {
        // Swift's split omits empty subsequences, matching Android's
        // split(" ").count { isNotBlank() }. A tab does not separate words
        // on either platform. wordCount is currently unused by any rule.
        XCTAssertEqual(intValue(facts("one  two three"), "wordCount"), 3)
        XCTAssertEqual(intValue(facts("one\ttwo three"), "wordCount"), 2)
        XCTAssertEqual(intValue(facts(""), "wordCount"), 0)
    }

    func testConversationTurns_isHistorySize() {
        XCTAssertEqual(intValue(facts("hi"), "conversationTurns"), 0)
        XCTAssertEqual(intValue(facts("hi", turns: 7), "conversationTurns"), 7)
    }

    func testHasImage_isPassedThrough() {
        XCTAssertFalse(boolValue(facts("look"), "hasImage"))
        XCTAssertTrue(boolValue(facts("look", hasImage: true), "hasImage"))
    }

    func testHasCodeBlock_detectsTripleBackticks() {
        XCTAssertFalse(boolValue(facts("plain question"), "hasCodeBlock"))
        XCTAssertTrue(boolValue(facts("fix this:\n```swift\nlet x = 1\n```"), "hasCodeBlock"))
    }

    func testHasMathSymbols_detectsOperators() {
        XCTAssertFalse(boolValue(facts("tell me a joke"), "hasMathSymbols"))
        XCTAssertTrue(boolValue(facts("what is 2+2"), "hasMathSymbols"))
        XCTAssertTrue(boolValue(facts("solve x^2 = 4"), "hasMathSymbols"))
    }

    func testSemanticFacts_matchLiteralKeywordsOnly() {
        // Documents the known weakness (docs/ROUTING.md §1): substring match,
        // case-insensitive on the lowercased prompt, no paraphrase coverage.
        XCTAssertTrue(boolValue(facts("LATEST NEWS about the match"), "mentionsCurrentEvents"))
        XCTAssertFalse(boolValue(facts("who won the game yesterday?"), "mentionsCurrentEvents"))
        XCTAssertTrue(boolValue(facts("can i sue my landlord"), "mentionsSensitiveDomain"))
        XCTAssertTrue(boolValue(facts("please analyze the data"), "requestsDeepReasoning"))
        XCTAssertTrue(boolValue(facts("write a poem about snow"), "requestsCreativeWriting"))
    }
}
