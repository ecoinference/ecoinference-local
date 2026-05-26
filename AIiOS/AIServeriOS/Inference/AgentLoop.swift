import Foundation

// MARK: - ParsedToolCall

struct ParsedToolCall {
    /// Any assistant text that appeared before the <tool_call> tag.
    let textBefore: String
    let toolName:   String
    let args:       [String: Any]
}

// MARK: - AgentLoop

/// Pure parsing logic for the client-side agentic tool loop.
/// Mirrors Flutter's AgentLoop class — detection, JSON parsing, and
/// result-message construction.
enum AgentLoop {

    /// Maximum agentic iterations per user turn before giving up.
    static let maxIterations = 2

    // ── Detection ─────────────────────────────────────────────────────────────

    /// Returns true if `response` appears to contain a tool-call opening tag.
    static func hasToolCall(_ response: String) -> Bool {
        response.contains("<tool_call>") || response.contains("<|tool_call>")
    }

    // ── Parsing ───────────────────────────────────────────────────────────────

    /// Parses a tool call from `response`.
    /// Returns nil if no valid tool call is found.
    static func parse(_ response: String) -> ParsedToolCall? {
        // Locate opening tag (plain or Gemma native <|tool_call>)
        let openPatterns = ["<tool_call>", "<|tool_call>", "<|tool_call >"]
        var openStart: String.Index? = nil
        var contentStart: String.Index? = nil

        for pat in openPatterns {
            if let r = response.range(of: pat) {
                openStart    = r.lowerBound
                contentStart = r.upperBound
                break
            }
        }
        guard let oStart = openStart, let cStart = contentStart else { return nil }

        let textBefore = String(response[response.startIndex..<oStart])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Locate closing tag
        let closePatterns = ["</tool_call>", "<tool_call|>"]
        var contentEnd: String.Index = response.endIndex
        for pat in closePatterns {
            if let r = response.range(of: pat, range: cStart..<response.endIndex) {
                contentEnd = r.lowerBound
                break
            }
        }

        var jsonStr = String(response[cStart..<contentEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown fences if present
        jsonStr = jsonStr
            .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$",          with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Gemma native format: call:TOOLNAME{...}
        if jsonStr.hasPrefix("call:") {
            let afterCall = jsonStr.dropFirst(5) // strip "call:"
            if let braceIdx = afterCall.firstIndex(of: "{") {
                let toolName = String(afterCall[afterCall.startIndex..<braceIdx])
                    .trimmingCharacters(in: .whitespaces)
                let rawArgs  = String(afterCall[braceIdx...])
                jsonStr = "{\"name\":\"\(toolName)\",\"args\":\(normalizeRelaxedJSON(rawArgs))}"
            }
        }

        // 3-attempt JSON parse
        if let result = tryParse(jsonStr, textBefore: textBefore)                { return result }
        let escaped = escapeControlCharsInStrings(jsonStr)
        if let result = tryParse(escaped, textBefore: textBefore)                { return result }
        let closed  = autoCloseJSON(escaped)
        if let result = tryParse(closed,  textBefore: textBefore)                { return result }
        return nil
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    private static func tryParse(_ jsonStr: String, textBefore: String) -> ParsedToolCall? {
        guard let data  = jsonStr.data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name  = obj["name"] as? String, !name.isEmpty
        else { return nil }
        let args = (obj["args"] as? [String: Any]) ?? (obj["arguments"] as? [String: Any]) ?? [:]
        return ParsedToolCall(textBefore: textBefore, toolName: name, args: args)
    }

    /// Converts JS-style object notation (unquoted keys) to valid JSON.
    /// e.g. {query:"foo"} → {"query":"foo"}
    private static func normalizeRelaxedJSON(_ s: String) -> String {
        // Quote unquoted keys: after { or , and before :
        let pattern = "([{,]\\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\\s*:)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = s
        // Work backwards so ranges stay valid
        let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed()
        for m in matches {
            let full  = m.range(at: 0)
            let pre   = m.range(at: 1)
            let key   = m.range(at: 2)
            let colon = m.range(at: 3)
            let replacement = ns.substring(with: pre) + "\"" + ns.substring(with: key) + "\"" + ns.substring(with: colon)
            result = (result as NSString).replacingCharacters(in: full, with: replacement)
        }
        return result
    }

    /// Appends missing closing braces/brackets to truncated JSON.
    private static func autoCloseJSON(_ s: String) -> String {
        var stack:    [Character] = []
        var inString  = false
        var escaped   = false
        for ch in s {
            if escaped           { escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\""        { inString = !inString; continue }
            if inString          { continue }
            if ch == "{"         { stack.append("}") }
            else if ch == "["    { stack.append("]") }
            else if ch == "}" || ch == "]" { if !stack.isEmpty { stack.removeLast() } }
        }
        return s + String(stack.reversed())
    }

    /// Escapes literal control characters (newline, tab, CR) that appear
    /// inside JSON string values — the most common model formatting error.
    private static func escapeControlCharsInStrings(_ s: String) -> String {
        var result   = ""
        var inString = false
        var escaped  = false
        for ch in s {
            if escaped {
                result.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && inString {
                result.append(ch)
                escaped = true
                continue
            }
            if ch == "\"" {
                inString = !inString
                result.append(ch)
                continue
            }
            if inString {
                switch ch {
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                default:   result.append(ch)
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    // ── Message construction ──────────────────────────────────────────────────

    /// Builds the InferenceMessage that feeds a tool result back to the LLM.
    /// Gemma has no native tool role, so results are injected as user turns.
    static func toolResultMessage(toolName: String, result: String) -> InferenceMessage {
        InferenceMessage(
            role: "user",
            text: "[Tool result: \(toolName)] \(result)\n" +
                  "The tool has completed. Respond with a brief natural-language summary of the result. " +
                  "Do NOT call any more tools."
        )
    }
}
