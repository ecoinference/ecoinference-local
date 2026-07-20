import Foundation
import FirebaseAuth

enum B2Error: LocalizedError {
    case notAuthenticated
    case functionError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:      return "You must be signed in to download models."
        case .functionError(let m):  return "Could not get download URL: \(m)"
        case .invalidResponse:       return "Unexpected response from server."
        }
    }
}

final class B2Service {

    static let shared = B2Service()
    private init() {}

    private let functionBase = "https://us-central1-ecoinference-28c31.cloudfunctions.net"

    /// Returns a presigned GET URL for the given model file.
    func modelDownloadUrl(modelId: String, filename: String) async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw B2Error.notAuthenticated
        }
        let idToken = try await user.getIDTokenResult().token

        var request = URLRequest(url: URL(string: "\(functionBase)/getModelDownloadUrl")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": ["modelId": modelId, "filename": filename, "platform": "mobile"]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw B2Error.functionError(msg)
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result  = json["result"] as? [String: Any],
            let urlStr  = result["url"] as? String,
            let presigned = URL(string: urlStr)
        else {
            throw B2Error.invalidResponse
        }

        return presigned
    }
}
