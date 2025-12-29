import SwiftUI

struct ChatView: View {
    let session: Session
    @StateObject private var messageManager = MessageManager()
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var refreshID = UUID()

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
                    .id(refreshID)
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
            do {
                _ = try await messageManager.sendMessage(sessionID: session.id, prompt: messageText)

                for i in 0..<30 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)

                    try await messageManager.fetchMessages(sessionID: session.id)
                    refreshID = UUID()
                    print("Poll iteration \(i): fetched \(messageManager.messages.count) messages")

                    if messageManager.messages.last?.role == .assistant {
                        print("Assistant response received!")
                        break
                    }
                }
            } catch {
                print("Error sending message: \(error)")
                inputText = messageText
            }
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

