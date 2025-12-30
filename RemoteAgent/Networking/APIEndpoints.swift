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

    func sendMessageWithStream(sessionID: String, prompt: String, directory: String? = nil) -> AsyncThrowingStream<APIResponseMessage, Error> {
        struct SendMessageBody: Encodable {
            let parts: [MessagePartData]
        }

        struct MessagePartData: Encodable {
            let type: String
            let text: String
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "/session/\(sessionID)/message"
                    let url = baseURL.appendingPathComponent(endpoint)
                    var request = URLRequest(url: url)
                    request.httpMethod = HTTPMethod.post.rawValue

                    if let directory = directory {
                        request.setValue(directory, forHTTPHeaderField: "x-opencode-directory")
                    }

                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let body = SendMessageBody(
                        parts: [
                            MessagePartData(type: "text", text: prompt)
                        ]
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    print("Starting stream to: \(url)")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          200..<300 ~= httpResponse.statusCode else {
                        print("Stream failed with status: \(response)")
                        continuation.finish(throwing: NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                        return
                    }

                    print("Stream started, reading lines...")
                    var buffer = ""
                    var lineCount = 0

                    for try await line in bytes.lines {
                        lineCount += 1
                        buffer += line + "\n"
                        print("Line \(lineCount): \(line.prefix(200))")

                        if line.isEmpty && !buffer.isEmpty {
                            print("Found complete message buffer, length: \(buffer.count)")
                            let data = extractData(from: buffer)
                            print("Extracted data: \(data.prefix(100))...")

                            if let message = try? JSONDecoder().decode(APIResponseMessage.self, from: Data(data.utf8)) {
                                print("Successfully decoded message: \(message.id), role: \(message.role.rawValue)")
                                continuation.yield(message)
                            } else {
                                print("Failed to decode message from: \(data)")
                            }

                            buffer = ""
                        }
                    }

                    print("Stream finished after \(lineCount) lines")

                    if !buffer.isEmpty {
                        print("Processing remaining buffer, length: \(buffer.count)")
                        let data = extractData(from: buffer)
                        print("Remaining data: \(data.prefix(100))...")

                        if let message = try? JSONDecoder().decode(APIResponseMessage.self, from: Data(data.utf8)) {
                            print("Successfully decoded message from buffer: \(message.id), role: \(message.role.rawValue)")
                            continuation.yield(message)
                        } else {
                            print("Failed to decode message from buffer")
                        }
                    }

                    continuation.finish()
                } catch {
                    print("Stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func extractData(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("data: ") {
                return String(trimmedLine.dropFirst(6))
            }
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
