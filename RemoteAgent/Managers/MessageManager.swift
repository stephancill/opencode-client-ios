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

    func clearMessages() {
        messages.removeAll()
    }
}
