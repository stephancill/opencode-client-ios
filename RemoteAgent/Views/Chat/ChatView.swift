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
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var autoScrollEnabled = true
    @FocusState private var isInputFocused: Bool
    @State private var sendTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Pending Permissions Alert
            if let pendingPermission = permissionManager.pendingPermissions.first(where: { $0.sessionID == session.id }) {
                PermissionAlertCard(
                    permission: pendingPermission,
                    onDeny: {
                        Task {
                            let _ = await permissionManager.respondToPermission(
                                sessionID: session.id,
                                permissionID: pendingPermission.id,
                                response: .reject,
                                directory: session.directory
                            )
                        }
                    },
                    onAllowOnce: {
                        Task {
                            let _ = await permissionManager.respondToPermission(
                                sessionID: session.id,
                                permissionID: pendingPermission.id,
                                response: .once,
                                directory: session.directory
                            )
                        }
                    },
                    onAllowAlways: {
                        Task {
                            let _ = await permissionManager.respondToPermission(
                                sessionID: session.id,
                                permissionID: pendingPermission.id,
                                response: .always,
                                directory: session.directory
                            )
                        }
                    }
                )
            }

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

    private func cancelRequest() {
        sendTask?.cancel()
        sendTask = nil

        Task {
            do {
                try await OpenCodeAPIClient.shared.abortSession(
                    sessionID: session.id,
                    directory: session.directory
                )
            } catch {
                print("Error aborting session: \(error)")
            }
        }

        isLoading = false
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
    @State private var isExpanded = false

    var body: some View {
        switch part.type {
        case .text:
            if let text = part.text {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            
        case .file:
            if let file = part.file {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            if let filename = file.filename {
                                Text(filename)
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            if let type = file.source?.type {
                                HStack(spacing: 4) {
                                    Text(type.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let path = file.source?.path {
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(path)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if let mime = file.mime {
                        Text(mime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            }
            
        case .tool:
            VStack(alignment: .leading, spacing: 0) {
                // Header with tool type and status
                HStack(spacing: 8) {
                    Image(systemName: toolIcon(part.tool))
                        .foregroundStyle(toolIconColor(part.tool))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // Show actual command from state.input.command or fallback to tool name
                        let displayCommand = part.state?.input?.command ?? part.state?.input?.filePath ?? part.tool ?? "Tool"
                        Text(displayCommand)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(isExpanded ? nil : 2)
                        
                        // Brief output preview when collapsed
                        if !isExpanded, let output = part.state?.output, !output.isEmpty {
                            Text(formatOutputPreview(output))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    if let status = part.state?.status {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 8, height: 8)
                            Text(status.capitalized)
                                .font(.caption2)
                                .foregroundStyle(statusColor(status))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                
                // Expandable details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        // Tool type label
                        if let toolName = part.tool {
                            Text("Tool: \(toolName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Full command display
                        if let command = part.state?.input?.command, !command.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Command")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(command)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(6)
                            }
                        }
                        
                        // File path for write/read operations
                        if let filePath = part.state?.input?.filePath, !filePath.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("File Path")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Image(systemName: "doc")
                                        .font(.caption)
                                    Text(filePath)
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        
                        // Description from state
                        if let description = part.state?.input?.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        
                        // File content for write operations (show preview)
                        if let content = part.state?.input?.content, !content.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Content (\(content.count) chars)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(content.prefix(500) + (content.count > 500 ? "..." : ""))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(6)
                            }
                        }
                        
                        // Tool output
                        if let output = part.state?.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Output")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                ScrollView {
                                    Text(output)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 200)
                                .padding(8)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(10)
                }
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
        case .reasoning:
            if let reasoning = part.reasoning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.purple)
                        Text("Thinking")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    
                    if isExpanded {
                        Text(reasoning)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(8)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }
            
        case .stepStart, .stepFinish:
            HStack(spacing: 6) {
                Image(systemName: part.type == .stepStart ? "play.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(part.type == .stepStart ? .blue : .green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.type == .stepStart ? "Step Started" : "Step Completed")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    if let time = part.time {
                        if let start = time.start, let end = time.end {
                            let duration = end - start
                            Text(formatDuration(duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(part.type == .stepStart ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
            .cornerRadius(8)
            
        case .patch:
            if let title = part.title {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("File Changed")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text(title)
                                .font(.body)
                        }
                    }
                    
                    if let snapshot = part.snapshot {
                        Text(snapshot)
                            .font(.body.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }
            
        case .snapshot:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(.cyan)
                    Text("Snapshot")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                if let snapshot = part.snapshot {
                    Text(snapshot)
                        .font(.body.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cyan.opacity(0.08))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyan.opacity(0.05))
            .cornerRadius(8)
            
        case .agent, .subtask, .retry, .compaction:
            // Handle other types simply
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(partTypeDisplay(part.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let text = part.text {
                    Text(text)
                        .font(.body)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        }
    }
    
    private func toolIcon(_ toolName: String?) -> String {
        guard let name = toolName?.lowercased() else { return "terminal" }
        
        if name.contains("read") || name.contains("cat") || name.contains("view") {
            return "eye"
        } else if name.contains("write") || name.contains("create") || name.contains("edit") {
            return "pencil"
        } else if name.contains("search") || name.contains("grep") || name.contains("find") {
            return "magnifyingglass"
        } else if name.contains("run") || name.contains("exec") {
            return "play.fill"
        } else if name.contains("delete") || name.contains("remove") {
            return "trash"
        } else if name.contains("git") {
            return "arrow.triangle.2.circlepath"
        } else if name.contains("test") {
            return "checkmark.shield"
        }
        
        return "terminal"
    }
    
    private func toolIconColor(_ toolName: String?) -> Color {
        guard let name = toolName?.lowercased() else { return .secondary }
        
        if name.contains("read") || name.contains("cat") || name.contains("view") {
            return .blue
        } else if name.contains("write") || name.contains("create") || name.contains("edit") {
            return .green
        } else if name.contains("search") || name.contains("grep") || name.contains("find") {
            return .orange
        } else if name.contains("run") || name.contains("exec") {
            return .purple
        } else if name.contains("delete") || name.contains("remove") {
            return .red
        } else if name.contains("git") {
            return .indigo
        }
        
        return .secondary
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "pending", "in_progress":
            return .blue
        case "completed", "success", "done":
            return .green
        case "error", "failed":
            return .red
        default:
            return .secondary
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        }
    }
    
    private func partTypeDisplay(_ type: MessagePartType) -> String {
        switch type {
        case .agent: return "Agent"
        case .subtask: return "Subtask"
        case .retry: return "Retry"
        case .compaction: return "Compaction"
        default: return type.rawValue
        }
    }
    
    private func formatOutputPreview(_ output: String) -> String {
        // Clean up newlines and show first ~100 chars
        let cleaned = output.replacingOccurrences(of: "\n", with: " ")
                                     .trimmingCharacters(in: .whitespaces)
        if cleaned.count > 100 {
            return String(cleaned.prefix(100)) + "..."
        }
        return cleaned
    }

// MARK: - Permission Alert Card
struct PermissionAlertCard: View {
    let permission: Permission
    let onDeny: () -> Void
    let onAllowOnce: () -> Void
    let onAllowAlways: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: permissionIcon(permission.type))
                    .foregroundStyle(permissionColor(permission.type))
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission Required")
                        .font(.headline)

                    Text(permission.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider()

            if let metadata = permission.metadata {
                ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                    if let value = metadata[key] {
                        HStack {
                            Text(key.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)

                            Text(value)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Deny") {
                    onDeny()
                }
                .buttonStyle(.bordered)

                Button("Allow Once") {
                    onAllowOnce()
                }
                .buttonStyle(.borderedProminent)

                Button("Always Allow") {
                    onAllowAlways()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func permissionIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "command", "execute", "run":
            return "terminal"
        case "file", "read", "write", "edit":
            return "doc.text"
        case "network", "http", "request":
            return "globe"
        case "system", "shell":
            return "gear"
        case "external_directory":
            return "folder.badge.questionmark"
        default:
            return "questionmark.circle"
        }
    }

    private func permissionColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "command", "execute", "run":
            return .red
        case "file", "read":
            return .blue
        case "write", "edit":
            return .orange
        case "network", "http":
            return .purple
        case "system", "shell":
            return .gray
        case "external_directory":
            return .orange
        default:
            return .secondary
        }
    }
}
