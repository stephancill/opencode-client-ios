import Foundation

struct HealthResponse: Decodable {
    let healthy: Bool
    let version: String
}

extension OpenCodeAPIClient {
    func getHealth() async throws -> HealthResponse {
        return try await performRequest(endpoint: "/global/health")
    }

    func listSessions(directory: String? = nil) async throws -> [Session] {
        return try await performRequest(endpoint: "/session", directory: directory)
    }

    func createSession(title: String? = nil, directory: String? = nil) async throws -> Session {
        struct CreateBody: Encodable {
            let title: String?
        }
        let body = CreateBody(title: title)
        return try await performRequest(endpoint: "/session", method: .post, body: body, directory: directory)
    }

    func getSession(id: String, directory: String? = nil) async throws -> Session {
        return try await performRequest(endpoint: "/session/\(id)", directory: directory)
    }

    func deleteSession(id: String, directory: String? = nil) async throws {
        return try await performRequestWithoutResponse(endpoint: "/session/\(id)", method: .delete, directory: directory)
    }

    func getMessages(sessionID: String, limit: Int? = nil, directory: String? = nil) async throws -> [APIResponseMessage] {
        var endpoint = "/session/\(sessionID)/message"
        if let limit = limit {
            endpoint += "?limit=\(limit)"
        }
        return try await performRequest(endpoint: endpoint, directory: directory)
    }

    func sendMessage(sessionID: String, prompt: String, directory: String? = nil) async throws -> Bool {
        struct SendMessageBody: Encodable {
            let parts: [MessagePartData]
        }

        struct MessagePartData: Encodable {
            let type: String
            let text: String
        }

        let body = SendMessageBody(
            parts: [
                MessagePartData(type: "text", text: prompt)
            ]
        )
        try await performRequestWithoutResponse(endpoint: "/session/\(sessionID)/prompt_async", method: .post, body: body, directory: directory)
        return true
    }

    func abortSession(sessionID: String, directory: String? = nil) async throws {
        return try await performRequestWithoutResponse(endpoint: "/session/\(sessionID)/abort", method: .post, directory: directory)
    }

    func listPermissions(directory: String? = nil) async throws -> [Permission] {
        return try await performRequest(endpoint: "/permission", directory: directory)
    }

    func respondToPermission(sessionID: String, permissionID: String, response: PermissionResponse, directory: String? = nil) async throws {
        struct ResponseBody: Encodable {
            let response: String
        }
        let body = ResponseBody(response: response.rawValue)
        return try await performRequestWithoutResponse(endpoint: "/session/\(sessionID)/permissions/\(permissionID)", method: .post, body: body, directory: directory)
    }

    func subscribeToGlobalEvents() -> SSEClient {
        let url = URL(string: baseURL.absoluteString + "/global/event")!
        return SSEClient(url: url)
    }

    func subscribeToDirectoryEvents(directory: String) -> SSEClient {
        let endpoint = "/event?directory=\(directory)"
        let url = URL(string: baseURL.absoluteString + endpoint)!
        return SSEClient(url: url)
    }
}
