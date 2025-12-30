import SwiftUI

func patternDisplayText(_ pattern: PermissionPattern) -> String {
    switch pattern {
    case .string(let string):
        return string
    case .array(let array):
        return array.joined(separator: ", ")
    }
}

struct PermissionAlertView: View {
    let permission: Permission
    let onDeny: () -> Void
    let onAllowOnce: () -> Void
    let onAllowAlways: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: permissionIcon(permission.type))
                    .font(.title2)
                    .foregroundStyle(permissionColor(permission.type))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.title)
                        .font(.headline)
                    
                    Text(permission.type.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let metadata = permission.metadata, !metadata.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top, spacing: 8) {
                                Text(key.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(metadata[key] ?? "")
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                
                if let pattern = permission.pattern {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pattern")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(patternDisplayText(pattern))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(6)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Button(action: onDeny) {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action: onAllowOnce) {
                    Text("Allow Once")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: onAllowAlways) {
                    Text("Always Allow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 12)
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
        default:
            return .secondary
        }
    }
}

struct PermissionListView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        NavigationStack {
            List {
                if permissionManager.pendingPermissions.isEmpty {
                    ContentUnavailableView {
                        Label("No pending permissions", systemImage: "checkmark.shield")
                    } description: {
                        Text("All permission requests have been handled")
                    }
                } else {
                    ForEach(permissionManager.pendingPermissions) { permission in
                        PermissionRow(permission: permission)
                    }
                }
            }
            .navigationTitle("Permissions")
            .refreshable {
                await permissionManager.fetchPermissions()
            }
        }
    }
}

struct PermissionRow: View {
    let permission: Permission
    @State private var showingDetails = false
    
    var body: some View {
        Button(action: { showingDetails = true }) {
            HStack(spacing: 12) {
                Image(systemName: permissionIcon(permission.type))
                    .font(.title2)
                    .foregroundStyle(permissionColor(permission.type))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(permission.type.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetails) {
            PermissionDetailView(permission: permission)
        }
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
        default:
            return .secondary
        }
    }
}

struct PermissionDetailView: View {
    let permission: Permission
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        Image(systemName: permissionIcon(permission.type))
                            .font(.largeTitle)
                            .foregroundStyle(permissionColor(permission.type))
                            .frame(width: 60, height: 60)
                            .background(permissionColor(permission.type).opacity(0.1))
                            .cornerRadius(12)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(permission.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(permission.type.uppercased())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(16)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.headline)
                        
                        if let metadata = permission.metadata, !metadata.isEmpty {
                            ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(key.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(metadata[key] ?? "")
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.03))
                                        .cornerRadius(6)
                                }
                            }
                        }
                        
                        if let pattern = permission.pattern {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pattern")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(patternDisplayText(pattern))
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.08))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 12) {
                        Button(action: { handleResponse(.reject) }) {
                            Text("Deny")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isProcessing)
                        
                        Button(action: { handleResponse(.once) }) {
                            Text("Allow Once")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isProcessing)
                        
                        Button(action: { handleResponse(.always) }) {
                            Text("Always Allow")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                        .disabled(isProcessing)
                    }
                }
                .padding()
            }
            .navigationTitle("Permission Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func handleResponse(_ response: PermissionResponse) {
        isProcessing = true
        Task {
            let success = await PermissionManager.shared.respondToPermission(
                sessionID: permission.sessionID,
                permissionID: permission.id,
                response: response
            )
            
            await MainActor.run {
                isProcessing = false
                if success {
                    dismiss()
                }
            }
        }
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
        default:
            return .secondary
        }
    }
}

#Preview {
    PermissionListView()
}
