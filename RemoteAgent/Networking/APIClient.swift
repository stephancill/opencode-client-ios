import Foundation
import Combine

enum OpenCodeError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case encodingError(Error)
    case serverError(code: String, message: String)
    case notFound
    case unauthorized
    case sessionBusy(sessionID: String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return message ?? "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error [\(code)]: \(message)"
        case .notFound:
            return "Resource not found"
        case .unauthorized:
            return "Unauthorized access"
        case .sessionBusy(let sessionID):
            return "Session \(sessionID) is busy"
        }
    }
}

class OpenCodeAPIClient {
    static let shared = OpenCodeAPIClient()

    var baseURL: URL {
        let baseURLString = UserDefaults.standard.string(forKey: "baseURL") ?? "https://vps.ts.net"
        var urlString = baseURLString

        if urlString.contains("localhost") {
            urlString = urlString.replacingOccurrences(of: "localhost", with: "127.0.0.1")
        }

        return URL(string: urlString) ?? URL(string: "https://vps.ts.net")!
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func setBaseURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "baseURL")
    }

    func performRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        directory: String? = nil
    ) async throws -> T {
        var request = try buildRequest(endpoint: endpoint, method: method, body: body, directory: directory)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let responseString = String(data: data, encoding: .utf8) ?? "No data"
            print("HTTP Error \(httpResponse.statusCode): \(responseString)")
            let errorMessage = try? JSONDecoder().decode([String: String].self, from: data)["message"]
            throw OpenCodeError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Decoding error for \(T.self): \(error)")
            throw OpenCodeError.decodingError(error)
        }
    }

    func performRequestWithoutResponse(
        endpoint: String,
        method: HTTPMethod = .post,
        body: Encodable? = nil,
        directory: String? = nil
    ) async throws {
        let request = try buildRequest(endpoint: endpoint, method: method, body: body, directory: directory)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw OpenCodeError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    private func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        directory: String?
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let directory = directory {
            request.setValue(directory, forHTTPHeaderField: "x-opencode-directory")
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        return request
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}
