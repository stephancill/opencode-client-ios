import Foundation

struct HealthResponse: Decodable {
    let healthy: Bool
    let version: String
}

extension OpenCodeAPIClient {
    func getHealth() async throws -> HealthResponse {
        return try await performRequest(endpoint: "/global/health")
    }

    func listSessions() async throws -> [Session] {
        return try await performRequest(endpoint: "/session")
    }

    func createSession(title: String? = nil) async throws -> Session {
        struct CreateBody: Encodable {
            let title: String?
        }
        let body = CreateBody(title: title)
        return try await performRequest(endpoint: "/session", method: .post, body: body)
    }

    func getSession(id: String) async throws -> Session {
        return try await performRequest(endpoint: "/session/\(id)")
    }

    func deleteSession(id: String) async throws {
        return try await performRequestWithoutResponse(endpoint: "/session/\(id)", method: .delete)
    }

    func getMessages(sessionID: String, limit: Int? = nil) async throws -> [APIResponseMessage] {
        var endpoint = "/session/\(sessionID)/message"
        if let limit = limit {
            endpoint += "?limit=\(limit)"
        }
        return try await performRequest(endpoint: endpoint)
    }

    func sendMessage(sessionID: String, prompt: String, agent: String? = nil) async throws -> Bool {
        struct SendMessageBody: Encodable {
            let parts: [MessagePartData]
            let agent: String?
        }

        struct MessagePartData: Encodable {
            let type: String
            let text: String
        }

        let body = SendMessageBody(
            parts: [
                MessagePartData(type: "text", text: prompt)
            ],
            agent: agent
        )
        try await performRequestWithoutResponse(endpoint: "/session/\(sessionID)/prompt_async", method: .post, body: body)
        return true
    }

    func sendMessageWithStream(sessionID: String, prompt: String) -> AsyncThrowingStream<APIResponseMessage, Error> {
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
                        print("Line \(lineCount): \(line.prefix(300))")
                        
                        // Try to decode each line directly as JSON first (for non-SSE responses)
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedLine.isEmpty {
                            // Check if it's a data: prefixed SSE line
                            let jsonContent: String
                            if trimmedLine.hasPrefix("data: ") {
                                jsonContent = String(trimmedLine.dropFirst(6))
                            } else if trimmedLine.hasPrefix("{") {
                                // Direct JSON
                                jsonContent = trimmedLine
                            } else {
                                // Accumulate into buffer for multi-line SSE
                                buffer += line + "\n"
                                continue
                            }
                            
                            print("Attempting to decode JSON: \(jsonContent.prefix(100))...")
                            if let message = try? JSONDecoder().decode(APIResponseMessage.self, from: Data(jsonContent.utf8)) {
                                print("Successfully decoded message: \(message.id), role: \(message.role.rawValue)")
                                continuation.yield(message)
                            } else {
                                print("Failed to decode message, accumulating in buffer")
                                buffer += line + "\n"
                            }
                        } else if !buffer.isEmpty {
                            // Empty line signals end of SSE event
                            print("Found empty line, processing buffer of length: \(buffer.count)")
                            let data = extractData(from: buffer)
                            print("Extracted data: \(data.prefix(100))...")

                            if let message = try? JSONDecoder().decode(APIResponseMessage.self, from: Data(data.utf8)) {
                                print("Successfully decoded message from buffer: \(message.id), role: \(message.role.rawValue)")
                                continuation.yield(message)
                            } else {
                                print("Failed to decode message from buffer: \(data.prefix(200))")
                            }
                            buffer = ""
                        }
                    }

                    print("Stream finished after \(lineCount) lines")

                    if !buffer.isEmpty {
                        print("Processing remaining buffer, length: \(buffer.count)")
                        let data = extractData(from: buffer)
                        print("Remaining data: \(data.prefix(200))...")

                        if let message = try? JSONDecoder().decode(APIResponseMessage.self, from: Data(data.utf8)) {
                            print("Successfully decoded message from remaining buffer: \(message.id), role: \(message.role.rawValue)")
                            continuation.yield(message)
                        } else {
                            print("Failed to decode message from remaining buffer")
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

    func abortSession(sessionID: String) async throws {
        return try await performRequestWithoutResponse(endpoint: "/session/\(sessionID)/abort", method: .post)
    }

    func listPermissions() async throws -> [Permission] {
        return try await performRequest(endpoint: "/permission")
    }

    func respondToPermission(sessionID: String, permissionID: String, response: PermissionResponse) async throws {
        struct ResponseBody: Encodable {
            let response: String
        }
        let body = ResponseBody(response: response.rawValue)
        
        let url = baseURL.appendingPathComponent("/session/\(sessionID)/permissions/\(permissionID)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        print("Sending permission response to: \(url)")
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }
        
        print("Permission response status: \(httpResponse.statusCode)")
        guard 200..<300 ~= httpResponse.statusCode else {
            throw OpenCodeError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    func subscribeToGlobalEvents() -> SSEClient {
        let url = URL(string: baseURL.absoluteString + "/global/event")!
        return SSEClient(url: url)
    }


}
