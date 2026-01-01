import SwiftUI

struct SessionsView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var isLoading = false
    @State private var isCreatingSession = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if isLoading {
                    ProgressView("Loading sessions...")
                } else if sessionManager.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No sessions yet", systemImage: "tray")
                            Text("Tap + to create a new session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sessionManager.sessions) { session in
                        NavigationLink(value: session) {
                            SessionRow(session: session)
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: Session.self) { session in
                ChatView(session: session)
            }
            .onAppear {
                loadSessions()
            }
            .refreshable {
                await loadSessionsAsync()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        createNewSession()
                    } label: {
                        if isCreatingSession {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(isCreatingSession)
                }
            }
        }
    }
    
    private func createNewSession() {
        isCreatingSession = true
        Task {
            await sessionManager.createSession(title: nil)
            isCreatingSession = false
            // Navigate to the newly created session
            if let newSession = sessionManager.currentSession {
                navigationPath.append(newSession)
            }
        }
    }

    private func loadSessions() {
        isLoading = true
        Task {
            await loadSessionsAsync()
            isLoading = false
        }
    }

    private func loadSessionsAsync() async {
        await sessionManager.loadSessions()
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)

            HStack(spacing: 8) {
                Text(formatDate(session.time.updated))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(session.directory)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationView {
        SessionsView()
    }
}
