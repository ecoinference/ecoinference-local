import XCTest
// No `@testable import` — PythonCommand.swift is compiled directly into this
// standalone test bundle (no host app), same pattern as AgentLoopTests.

final class PythonCommandTests: XCTestCase {

    func testExtractCode_matchedPythonFence() {
        let response = "Here you go:\n```python\nresult = 1 + 1\n```\nDone."
        XCTAssertEqual(PythonCommand.extractCode(from: response), "result = 1 + 1")
    }

    func testExtractCode_matchedGenericFence() {
        let response = "```\nresult = 1 + 1\n```"
        XCTAssertEqual(PythonCommand.extractCode(from: response), "result = 1 + 1")
    }

    // Reproduces the exact failure seen live on-device 2026-07-28: the model
    // starts straight into code with no opening fence, but still tacks on a
    // trailing ``` — leaving it in "code" guarantees a Python syntax error.
    func testExtractCode_trailingFenceOnly_noOpeningFence() {
        let response = """
        import matplotlib.pyplot as plt
        import numpy as np
        x = np.linspace(0, 2 * np.pi, 100)
        plt.plot(x, np.sin(x))
        ```
        """
        let code = PythonCommand.extractCode(from: response)
        XCTAssertFalse(code?.contains("```") ?? true, "extracted code must not contain a stray fence marker")
        XCTAssertEqual(code, """
        import matplotlib.pyplot as plt
        import numpy as np
        x = np.linspace(0, 2 * np.pi, 100)
        plt.plot(x, np.sin(x))
        """)
    }

    // The opposite case: an opening fence with no closing one (response cut
    // off mid-generation).
    func testExtractCode_openingFenceOnly_noClosingFence() {
        let response = "```python\nresult = 1 + 1"
        XCTAssertEqual(PythonCommand.extractCode(from: response), "result = 1 + 1")
    }

    func testExtractCode_noFencesAtAll() {
        let response = "result = 1 + 1"
        XCTAssertEqual(PythonCommand.extractCode(from: response), "result = 1 + 1")
    }

    func testExtractCode_emptyResponse() {
        XCTAssertNil(PythonCommand.extractCode(from: "   \n  "))
    }
}
