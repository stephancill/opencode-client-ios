import SwiftUI

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
