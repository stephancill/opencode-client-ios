import SwiftUI

struct SessionsView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var isCreatingSession = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if isLoading {
                    ForEach(0..<5, id: \.self) { _ in
                        SessionSkeletonView()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
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
                                .overlay(
                                    // Show subtle loading indicator during refresh
                                    Group {
                                        if isRefreshing {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                                .opacity(0.5)
                                        }
                                    }
                                )
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
            .overlay(
                VStack {
                    if isRefreshing && !sessionManager.sessions.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Refreshing...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    
                    if isCreatingSession {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                ProgressView("Creating session...")
                                    .padding()
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 4)
                                Spacer()
                            }
                            Spacer()
                        }
                        .background(Color.black.opacity(0.1))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            )
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
        if sessionManager.sessions.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        
        Task {
            await loadSessionsAsync()
            isLoading = false
            isRefreshing = false
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

            Text(formatDate(session.time.updated))
                .font(.caption)
                .foregroundStyle(.secondary)
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
