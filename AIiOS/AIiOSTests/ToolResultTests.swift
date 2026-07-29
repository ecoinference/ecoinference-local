import XCTest
// No `@testable import` — ToolResult.swift is compiled directly into this
// standalone test bundle (no host app), same pattern as AgentLoopTests.

final class ToolResultTests: XCTestCase {

    func testHumanReadable_wrapsSimpleErrorMessage() {
        let raw = #"{"error":"'code' parameter is required"}"#
        XCTAssertEqual(ToolResult.humanReadable(raw), "⚠️ 'code' parameter is required")
    }

    func testHumanReadable_extractsLastLineOfTraceback() {
        let raw = #"{"error":"Traceback (most recent call last):\n  File \"<string>\", line 1, in <module>\nZeroDivisionError: division by zero"}"#
        XCTAssertEqual(ToolResult.humanReadable(raw), "⚠️ ZeroDivisionError: division by zero")
    }

    func testHumanReadable_passesThroughPlainText() {
        let raw = "Tool 'nonexistent_tool' not found."
        XCTAssertEqual(ToolResult.humanReadable(raw), raw)
    }

    func testHumanReadable_passesThroughNonErrorJSON() {
        let raw = #"{"result":"42"}"#
        XCTAssertEqual(ToolResult.humanReadable(raw), raw)
    }

    func testHumanReadable_passesThroughMalformedJSON() {
        // A tool error whose message contains an unescaped quote produces
        // invalid JSON — must fall back to showing the raw string, not crash.
        let raw = #"{"error":"unterminated "quote" here"}"#
        XCTAssertEqual(ToolResult.humanReadable(raw), raw)
    }

    func testDisplayText_doesNotAffectModelText() {
        let result = ToolResult.text(#"{"error":"'code' parameter is required"}"#)
        XCTAssertEqual(result.modelText, #"{"error":"'code' parameter is required"}"#)
        XCTAssertEqual(result.displayText, "⚠️ 'code' parameter is required")
    }
}
