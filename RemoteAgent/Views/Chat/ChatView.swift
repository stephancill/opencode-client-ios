import SwiftUI

enum AgentMode: String, CaseIterable {
    case build = "build"
    case plan = "plan"
}

struct ChatView: View {
    let session: Session
    @StateObject private var messageManager = MessageManager()
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var mentionManager = MentionManager()
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var autoScrollEnabled = true
    @FocusState private var isInputFocused: Bool
    @State private var sendTask: Task<Void, Never>?
    @State private var permissionError: String?
    @State private var agentMode: AgentMode = .build

    var body: some View {
        VStack(spacing: 0) {
            if let pendingPermission = permissionManager.pendingPermissions.first(where: { $0.sessionID == session.id }) {
                PermissionAlertCard(
                    permission: pendingPermission,
                    error: permissionManager.error,
                    onDeny: {
                        Task {
                            print("Deny button pressed for permission \(pendingPermission.id)")
                            let _ = await permissionManager.respondToPermission(
                                sessionID: session.id,
                                permissionID: pendingPermission.id,
                                response: .reject
                            )
                        }
                    },
                    onAllowOnce: {
                        Task {
                            print("Allow Once button pressed for permission \(pendingPermission.id)")
                            let _ = await permissionManager.respondToPermission(
                                sessionID: session.id,
                                permissionID: pendingPermission.id,
                                response: .once
                            )
                        }
                    },
                    onAllowAlways: {
                        Task {
                            print("Always Allow button pressed for permission \(pendingPermission.id)")
                            let _ = await permissionManager.respondToPermission(
                                sessionID: session.id,
                                permissionID: pendingPermission.id,
                                response: .always
                            )
                        }
                    }
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if messageManager.messages.isEmpty {
                            if messageManager.isLoading {
                                ProgressView("Loading messages...")
                            } else {
                                ContentUnavailableView {
                                    Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                                        Text("Start a conversation")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ForEach(messageManager.messages, id: \.id) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottomAnchor")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messageManager.messages.count) { _, _ in
                    if autoScrollEnabled {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: messageManager.contentUpdateId) { _, _ in
                    if autoScrollEnabled {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }

            Divider()

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    AutocompleteView(
                        suggestions: mentionManager.suggestions,
                        onSelect: { suggestion in
                            let (newText, _) = mentionManager.selectSuggestion(suggestion, in: inputText)
                            inputText = newText
                        }
                    )
                    .padding(.horizontal)
                    .opacity(mentionManager.isAutocompleteVisible ? 1 : 0)
                    .frame(height: mentionManager.isAutocompleteVisible ? nil : 0)

                    Divider()
                        .opacity(mentionManager.isAutocompleteVisible ? 1 : 0)

                    HStack(alignment: .bottom, spacing: 12) {
                        if inputText.isEmpty {
                            Picker("", selection: $agentMode) {
                                Text("Build").tag(AgentMode.build)
                                Text("Plan").tag(AgentMode.plan)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }

                        TextField("Message", text: $inputText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...6)
                            .focused($isInputFocused)
                            .onChange(of: inputText) { oldValue, newValue in
                                mentionManager.handleTextChange(newValue, cursorPosition: newValue.count)
                            }
                            .onSubmit {
                                if !inputText.isEmpty && !isLoading {
                                    performSend()
                                }
                            }

                        Button(action: isLoading ? cancelRequest : performSend) {
                            if isLoading {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
                            }
                        }
                        .disabled(inputText.isEmpty && !isLoading)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(session.title)
        .task {
            await loadMessages()
            await permissionManager.fetchPermissions()
            
            // Start event listener to catch streaming updates for existing sessions
            messageManager.startEventListener(sessionID: session.id)
        }
        .onDisappear {
            // Stop event listener when leaving the session
            messageManager.stopEventListener()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }

    private func loadMessages() async {
        do {
            try await messageManager.fetchMessages(sessionID: session.id)
        } catch {
            print("Error loading messages: \(error)")
        }
    }

    private func cancelRequest() {
        sendTask?.cancel()
        sendTask = nil

        Task {
            do {
                try await OpenCodeAPIClient.shared.abortSession(
                    sessionID: session.id
                )
            } catch {
                print("Error aborting session: \(error)")
            }
        }

        isLoading = false
    }

    private func performSend() {
        guard !inputText.isEmpty, !isLoading else { return }

        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        inputText = ""
        isLoading = true
        autoScrollEnabled = true
        isInputFocused = false
        mentionManager.hideAutocomplete()

        Task { @MainActor in
            print("ChatView: Starting to send message")

            let userMessage = createUserMessage(text: messageText)
            if let userMessage = userMessage {
                messageManager.messages.append(userMessage)
                print("ChatView: Added user message, count: \(messageManager.messages.count)")
            }

            let stream = messageManager.sendMessageWithStream(
                sessionID: session.id,
                prompt: messageText,
                agent: agentMode.rawValue
            )

            for await _ in stream {
            }

            print("ChatView: Stream completed")
            isLoading = false
        }
    }

    private func createUserMessage(text: String) -> APIResponseMessage? {
        let userMessageID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"
        let partID = "prt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"

        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        let userMessageJSON = """
        {
            "info": {
                "id": "\(userMessageID)",
                "sessionID": "\(session.id)",
                "role": "user",
                "time": {
                    "created": \(Int(Date().timeIntervalSince1970 * 1000))
                }
            },
            "parts": [
                {
                    "id": "\(partID)",
                    "sessionID": "\(session.id)",
                    "messageID": "\(userMessageID)",
                    "type": "text",
                    "text": "\(escapedText)"
                }
            ]
        }
        """

        guard let data = userMessageJSON.data(using: .utf8) else {
            print("ChatView: Failed to create user message data")
            return nil
        }

        do {
            return try JSONDecoder().decode(APIResponseMessage.self, from: data)
        } catch {
            print("ChatView: Failed to decode user message: \(error)")
            return nil
        }
    }
}
