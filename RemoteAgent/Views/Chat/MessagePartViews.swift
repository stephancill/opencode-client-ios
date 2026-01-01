import SwiftUI

struct MessagePartRow: View {
    let part: MessagePart
    @State private var isExpanded = false

    var body: some View {
        switch part.type {
        case .text:
            if let text = part.text {
                MarkdownView(content: text)
            }

        case .file:
            if let file = part.file {
                FilePartView(file: file)
            }

        case .tool:
            ToolPartView(part: part, isExpanded: $isExpanded)

        case .reasoning:
            if let reasoning = part.reasoning {
                ReasoningPartView(reasoning: reasoning, isExpanded: $isExpanded)
            }

        case .stepStart, .stepFinish:
            StepPartView(part: part)

        case .patch:
            if let title = part.title {
                PatchPartView(title: title, snapshot: part.snapshot)
            }

        case .snapshot:
            SnapshotPartView(snapshot: part.snapshot)

        case .agent, .subtask, .retry, .compaction:
            GenericPartView(part: part)
        }
    }
}

struct FilePartView: View {
    let file: MessagePart.FilePart

    var body: some View {
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
}

struct ToolPartView: View {
    let part: MessagePart
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: toolIcon(part.tool))
                    .foregroundStyle(toolIconColor(part.tool))

                VStack(alignment: .leading, spacing: 2) {
                    let displayCommand = part.state?.input?.command ?? part.state?.input?.filePath ?? part.tool ?? "Tool"
                    Text(displayCommand)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(isExpanded ? nil : 2)

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

            if isExpanded {
                ToolExpandedView(part: part)
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
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

    private func formatOutputPreview(_ output: String) -> String {
        let cleaned = output.replacingOccurrences(of: "\n", with: " ")
                                      .trimmingCharacters(in: .whitespaces)
        if cleaned.count > 100 {
            return String(cleaned.prefix(100)) + "..."
        }
        return cleaned
    }
}

struct ToolExpandedView: View {
    let part: MessagePart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toolName = part.tool {
                Text("Tool: \(toolName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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

            if let description = part.state?.input?.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

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

struct ReasoningPartView: View {
    let reasoning: String
    @Binding var isExpanded: Bool

    var body: some View {
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
}

struct StepPartView: View {
    let part: MessagePart

    var body: some View {
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
}

struct PatchPartView: View {
    let title: String
    let snapshot: String?

    var body: some View {
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

            if let snapshot = snapshot {
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
}

struct SnapshotPartView: View {
    let snapshot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(.cyan)
                Text("Snapshot")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            if let snapshot = snapshot {
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
    }
}

struct GenericPartView: View {
    let part: MessagePart

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(partTypeDisplay(part.type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let text = part.text {
                MarkdownView(content: text)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
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
}
