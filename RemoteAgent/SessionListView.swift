import SwiftUI

struct SessionsView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var showingCreateAlert = false
    @State private var newSessionTitle = ""
    @State private var isLoading = false

    var body: some View {
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
                    NavigationLink {
                        ChatView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .onAppear {
            loadSessions()
        }
        .refreshable {
            await loadSessionsAsync()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Session", isPresented: $showingCreateAlert) {
            TextField("Title", text: $newSessionTitle)

            Button("Cancel", role: .cancel) { }

            Button("Create") {
                Task {
                    await sessionManager.createSession(title: newSessionTitle.isEmpty ? nil : newSessionTitle)
                    newSessionTitle = ""
                }
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
