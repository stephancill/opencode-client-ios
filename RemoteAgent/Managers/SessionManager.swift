import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var sessions: [Session] = []
    @Published var currentSession: Session?

    private init() {}

    func loadSessions() async {
        do {
            sessions = try await OpenCodeAPIClient.shared.listSessions()
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    func createSession(title: String? = nil) async {
        do {
            let newSession = try await OpenCodeAPIClient.shared.createSession(title: title)
            sessions.append(newSession)
            currentSession = newSession
        } catch {
            print("Failed to create session: \(error)")
        }
    }

    func deleteSession(_ session: Session) async {
        do {
            try await OpenCodeAPIClient.shared.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
            if currentSession?.id == session.id {
                currentSession = nil
            }
        } catch {
            print("Failed to delete session: \(error)")
        }
    }

    func selectSession(_ session: Session) {
        currentSession = session
    }
}
