import Foundation

enum UsernameValidator {
    // 4–16 chars, lowercase letters / digits / underscore only
    private static let regex = try! NSRegularExpression(pattern: "^[a-z0-9_]{4,16}$")

    enum ValidationError: LocalizedError {
        case tooShort, tooLong, invalidChars
        var errorDescription: String? {
            switch self {
            case .tooShort:     return "Username must be at least 4 characters."
            case .tooLong:      return "Username must be 16 characters or fewer."
            case .invalidChars: return "Only lowercase letters, numbers, and underscores."
            }
        }
    }

    static func validate(_ username: String) throws {
        if username.count < 4  { throw ValidationError.tooShort }
        if username.count > 16 { throw ValidationError.tooLong }
        let range = NSRange(username.startIndex..., in: username)
        if regex.firstMatch(in: username, range: range) == nil {
            throw ValidationError.invalidChars
        }
    }

    static func normalized(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .whitespaces)
    }
}
