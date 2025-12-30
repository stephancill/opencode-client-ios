import SwiftUI

struct PermissionAlertCard: View {
    let permission: Permission
    let error: String?
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

            if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
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
