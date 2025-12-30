import Foundation
import Combine

@MainActor
class MessageManager: ObservableObject {
    @Published var messages: [any Message] = []
    @Published var isLoading = false
    @Published var error: OpenCodeError?

    private let apiClient = OpenCodeAPIClient.shared
    private var cancellables = Set<AnyCancellable>()

    func fetchMessages(sessionID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.getMessages(sessionID: sessionID)
            messages = response
            error = nil
        } catch {
            if let openCodeError = error as? OpenCodeError {
                self.error = openCodeError
            } else {
                self.error = .networkError(error)
            }
            throw error
        }
    }

    func sendMessage(sessionID: String, prompt: String) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            return try await apiClient.sendMessage(sessionID: sessionID, prompt: prompt)
        } catch {
            if let openCodeError = error as? OpenCodeError {
                self.error = openCodeError
            } else {
                self.error = .networkError(error)
            }
            throw error
        }
    }

    func sendMessageWithStream(sessionID: String, prompt: String) -> AsyncStream<APIResponseMessage> {
        return AsyncStream { continuation in
            Task { @MainActor in
                isLoading = true
                print("MessageManager: Starting stream for session \(sessionID)")

                do {
                    let stream = apiClient.sendMessageWithStream(sessionID: sessionID, prompt: prompt)

                    for try await message in stream {
                        print("MessageManager: Received message \(message.id) with role \(message.role.rawValue)")
                        print("MessageManager: Current message count before update: \(messages.count)")

                        if message.role == .user && !messages.contains(where: { $0.id == message.id }) {
                            messages.append(message)
                            print("MessageManager: Added user message, new count: \(messages.count)")
                        } else if message.role == .assistant {
                            if let index = messages.firstIndex(where: { $0.role == .assistant && $0.id == message.id }) {
                                messages[index] = message
                                print("MessageManager: Updated assistant message at index \(index)")
                            } else {
                                messages.append(message)
                                print("MessageManager: Added new assistant message, new count: \(messages.count)")
                            }
                        }

                        continuation.yield(message)
                    }

                    error = nil
                } catch {
                    print("MessageManager: Stream error: \(error)")
                    if let openCodeError = error as? OpenCodeError {
                        self.error = openCodeError
                    } else {
                        self.error = .networkError(error)
                    }
                }

                isLoading = false
                continuation.finish()
                print("MessageManager: Stream finished, final message count: \(messages.count)")
            }
        }
    }

    func clearMessages() {
        messages.removeAll()
    }
}
