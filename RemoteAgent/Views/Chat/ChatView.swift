import SwiftUI

struct ChatView: View {
    let session: Session
    @StateObject private var messageManager = MessageManager()
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messageManager.messages.isEmpty {
                            ContentUnavailableView {
                                Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                                    Text("Start a conversation")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(messageManager.messages, id: \.id) { message in
                                MessageRow(message: message)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messageManager.messages.count) { _ in
                    if let lastMessage = messageManager.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)

                Button(action: sendMessage) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.blue)
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

    private func loadMessages() async {
        do {
            try await messageManager.fetchMessages(sessionID: session.id)
        } catch {
            print("Error loading messages: \(error)")
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        isLoading = true
        let messageText = inputText
        inputText = ""

        Task { @MainActor in
            print("ChatView: Starting to send message")

            let userMessageID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"
            let partID = "prt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"

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
                        "text": "\(messageText.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
                    }
                ]
            }
            """

            if let data = userMessageJSON.data(using: .utf8),
               let userMessage = try? JSONDecoder().decode(APIResponseMessage.self, from: data) {
                print("ChatView: Created user message: \(userMessageID)")
                messageManager.messages.append(userMessage)
                print("ChatView: Current message count after adding user message: \(messageManager.messages.count)")
            } else {
                print("ChatView: Failed to create user message")
            }

            let stream = messageManager.sendMessageWithStream(sessionID: session.id, prompt: messageText)

            for await message in stream {
                print("ChatView: Received message \(message.id) with role \(message.role.rawValue)")
                print("ChatView: Current message count: \(messageManager.messages.count)")
            }

            print("ChatView: Stream completed")
            isLoading = false
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

