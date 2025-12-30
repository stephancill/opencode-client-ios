import Foundation
import Combine

class SSEClient {
    private let url: URL
    private var bytesTask: URLSession.AsyncBytes?
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private let session: URLSession

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func connect() -> AsyncThrowingStream<SSEEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          200..<300 ~= httpResponse.statusCode else {
                        continuation.finish(throwing: NSError(domain: "SSEClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                        return
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        buffer += line + "\n"

                        if line.isEmpty && !buffer.isEmpty {
                            let events = parseSSE(content: buffer)
                            for event in events {
                                continuation.yield(event)
                            }
                            buffer = ""
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func connectToStream() -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            self.continuation = continuation

            Task {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          200..<300 ~= httpResponse.statusCode else {
                        continuation.finish(throwing: NSError(domain: "SSEClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                        return
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        buffer += line + "\n"

                        if line.isEmpty && !buffer.isEmpty {
                            if let data = extractData(from: buffer) {
                                continuation.yield(data)
                            }
                            buffer = ""
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func disconnect() {
        continuation?.finish()
        continuation = nil
    }

    private func parseSSE(content: String) -> [SSEEvent] {
        let lines = content.components(separatedBy: "\n")

        var currentType: String?
        var currentData: String?
        var events: [SSEEvent] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                if let type = currentType, let data = currentData {
                    events.append(SSEEvent(type: type, properties: parseData(data)))
                }
                currentType = nil
                currentData = nil
                continue
            }

            if trimmedLine.hasPrefix("data: ") {
                currentData = String(trimmedLine.dropFirst(6))
            } else if trimmedLine.hasPrefix("event: ") {
                currentType = String(trimmedLine.dropFirst(7))
            }
        }

        if let type = currentType, let data = currentData {
            events.append(SSEEvent(type: type, properties: parseData(data)))
        }

        return events
    }

    private func extractData(from content: String) -> String? {
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("data: ") {
                return String(trimmedLine.dropFirst(6))
            }
        }

        return nil
    }

    private func parseData(_ data: String) -> [String: Any] {
        guard let data = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return json
    }
}
