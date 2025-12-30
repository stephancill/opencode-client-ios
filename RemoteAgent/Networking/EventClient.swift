import Foundation

struct ServerEvent {
    let type: String
    let properties: [String: Any]
}

class EventClient {
    static let shared = EventClient()

    private let baseURL: URL
    private let session: URLSession
    private var currentTask: Task<Void, Never>?

    private init() {
        let baseURLString = UserDefaults.standard.string(forKey: "baseURL") ?? "https://vps.ts.net"
        var urlString = baseURLString

        if urlString.contains("localhost") || urlString.contains("127.0.0.1") {
            urlString = urlString.replacingOccurrences(of: "localhost", with: "127.0.0.1")
        }

        self.baseURL = URL(string: urlString)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        self.session = URLSession(configuration: config)
    }

    func eventStream(directory: String?) -> AsyncThrowingStream<ServerEvent, Error> {
        return AsyncThrowingStream { continuation in
            currentTask = Task {
                var urlString = baseURL.absoluteString
                if urlString.hasSuffix("/") {
                    urlString.removeLast()
                }

                if let directory = directory {
                    let encoded = directory.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? directory
                    urlString += "/event?directory=\(encoded)"
                } else {
                    urlString += "/event"
                }

                if let url = URL(string: urlString) {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 300

                    print("EventClient: Connecting to \(url.absoluteString)")

                    do {
                        let (bytes, response) = try await session.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse,
                              200..<300 ~= httpResponse.statusCode else {
                            throw NSError(domain: "EventClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response: \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
                        }

                        var buffer = ""

                        for try await byte in bytes {
                            if byte == 10 {
                                if !buffer.isEmpty {
                                    print("EventClient: Raw buffer: \(buffer)")
                                    if let data = buffer.data(using: .utf8),
                                       let event = parseServerEvent(data) {
                                        print("EventClient: Parsed event type: \(event.type)")
                                        continuation.yield(event)
                                    } else {
                                        print("EventClient: Failed to parse event from buffer")
                                    }
                                    buffer = ""
                                }
                            } else if byte != 13 {
                                buffer.append(Character(Unicode.Scalar(byte)))
                            }
                        }

                        continuation.finish()
                    } catch {
                        print("EventClient: Connection error: \(error)")
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func parseServerEvent(_ data: Data) -> ServerEvent? {
        var jsonString = String(data: data, encoding: .utf8) ?? ""

        if jsonString.hasPrefix("data:") {
            jsonString = String(jsonString.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }

        guard let json = try? JSONSerialization.jsonObject(with: jsonString.data(using: .utf8) ?? data) as? [String: Any],
              let type = json["type"] as? String,
              let properties = json["properties"] as? [String: Any] else {
            print("EventClient: Failed to parse event: \(jsonString)")
            return nil
        }

        return ServerEvent(type: type, properties: properties)
    }
}
