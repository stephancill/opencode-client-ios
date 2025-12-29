import Foundation
import Combine

class SSEClient {
    private let url: URL
    private var task: URLSessionDataTask?
    private var continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation?

    init(url: URL) {
        self.url = url
    }

    func connect() -> AsyncThrowingStream<SSEEvent, Error> {
        return AsyncThrowingStream { continuation in
            self.continuation = continuation

            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    continuation.finish(throwing: NSError(domain: "SSEClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                    return
                }

                guard let data = data,
                      let content = String(data: data, encoding: .utf8) else {
                    continuation.finish(throwing: NSError(domain: "SSEClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid data"]))
                    return
                }

                self.parseSSE(content: content) { event in
                    continuation.yield(event)
                }

                continuation.finish()
            }

            task?.resume()
        }
    }

    func disconnect() {
        task?.cancel()
        continuation?.finish()
        continuation = nil
    }

    private func parseSSE(content: String, onEvent: (SSEEvent) -> Void) {
        let lines = content.components(separatedBy: "\n")

        var currentType: String?
        var currentData: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                if let type = currentType, let data = currentData {
                    onEvent(SSEEvent(type: type, properties: parseData(data)))
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
            onEvent(SSEEvent(type: type, properties: parseData(data)))
        }
    }

    private func parseData(_ data: String) -> [String: Any] {
        guard let data = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return json
    }
}
