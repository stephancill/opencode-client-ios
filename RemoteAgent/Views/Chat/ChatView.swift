import SwiftUI

// PreferenceKey to track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    let session: Session
    @StateObject private var messageManager = MessageManager()
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var autoScrollEnabled = true
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if messageManager.messages.isEmpty && !isLoading {
                            ContentUnavailableView {
                                Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                                    Text("Start a conversation")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                            }
                        }
                        
                        ForEach(messageManager.messages, id: \.id) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        
                        // Invisible anchor at the bottom for scrolling
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
                    // Scroll when content updates (streaming) - no animation for smoother updates
                    if autoScrollEnabled {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .onSubmit {
                        if !inputText.isEmpty && !isLoading {
                            performSend()
                        }
                    }

                Button(action: performSend) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
                    }
                }
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding()
        }
        .navigationTitle(session.title)
        .task {
            await loadMessages()
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

    private func performSend() {
        guard !inputText.isEmpty, !isLoading else { return }
        
        // Capture the text and clear input immediately
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        
        // Clear input and set loading state
        inputText = ""
        isLoading = true
        autoScrollEnabled = true
        isInputFocused = false

        Task { @MainActor in
            print("ChatView: Starting to send message")
            
            // Create user message for immediate display
            let userMessage = createUserMessage(text: messageText)
            if let userMessage = userMessage {
                messageManager.messages.append(userMessage)
                print("ChatView: Added user message, count: \(messageManager.messages.count)")
            }

            // Stream the response
            let stream = messageManager.sendMessageWithStream(
                sessionID: session.id,
                prompt: messageText,
                directory: session.directory
            )

            for await _ in stream {
                // Updates are handled by messageManager
            }

            print("ChatView: Stream completed")
            isLoading = false
        }
    }
    
    private func createUserMessage(text: String) -> APIResponseMessage? {
        let userMessageID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"
        let partID = "prt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"
        
        // Escape text for JSON
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

struct MessageRow: View {
    let message: any Message

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .assistant {
                    Spacer()
                }

                VStack(alignment: message.role == .user ? .trailing : .leading) {
                    if let apiMsg = message as? APIResponseMessage {
                        switch apiMsg {
                        case .assistant(let assistantMsg):
                            AssistantMessageContentView(message: assistantMsg.info, parts: assistantMsg.parts)
                        case .user(let userMsg):
                            UserMessageContentView(message: userMsg.info, parts: userMsg.parts)
                        }
                    } else {
                        Text("Unknown message type")
                            .font(.body)
                    }
                }
                .padding()
                .background(message.role == .user ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(12)

                if message.role == .user {
                    Spacer()
                }
            }

            Text(formatDate(message.timeCreated))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct AssistantMessageContentView: View {
    let message: AssistantMessageInfo
    let parts: [MessagePart]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.agent)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = message.error, let errorMessage = error.message {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.red)
            }

            ForEach(parts) { part in
                MessagePartRow(part: part)
            }

            HStack(spacing: 8) {
                Image(systemName: "cpu")
                Text("\(message.tokens.input + message.tokens.output + message.tokens.reasoning) tokens")

                Image(systemName: "dollarsign.circle")
                Text(String(format: "%.4f", message.cost))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct UserMessageContentView: View {
    let message: UserMessageInfo
    let parts: [MessagePart]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(parts) { part in
                MessagePartRow(part: part)
            }

            if let summary = message.summary {
                if let title = summary.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct MessagePartRow: View {
    let part: MessagePart

    var body: some View {
        switch part.type {
        case .text:
            if let text = part.text {
                Text(text)
                    .font(.body)
            }
        case .file:
            if let file = part.file {
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                    if let filename = file.filename {
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
        case .tool:
            if let tool = part.tool {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    if let command = tool.command {
                        Text(command)
                            .font(.caption.monospaced())
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(6)
            }
        case .reasoning:
            if let reasoning = part.reasoning {
                Text(reasoning)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        case .stepStart, .stepFinish:
            HStack(spacing: 4) {
                Image(systemName: part.type == .stepStart ? "play.circle" : "stop.circle")
                Text(part.type == .stepStart ? "Step started" : "Step finished")
                    .font(.caption)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

