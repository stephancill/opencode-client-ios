import SwiftUI
import Foundation

struct SettingsView: View {
    @State private var baseURL: String
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingTokenCopied = false
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingResetConfirmation = false
    @State private var showingResetSuccess = false
    @State private var resetError = ""
    @State private var isResetting = false
    
    init() {
        _baseURL = State(initialValue: UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:3000")
    }
    
    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $baseURL)
                
                Text("Examples: http://localhost:3000, https://vps.ts.net")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("OpenCode Server")
            }
            
            Section {
                Button("Save & Test Connection") {
                    saveAndTest()
                }
                
                Button("Reset Instance") {
                    showingResetConfirmation = true
                }
                .foregroundStyle(.red)
            }
            
            Section {
                Toggle("Enable Notifications", isOn: $notificationManager.isEnabled)
                    .onChange(of: notificationManager.isEnabled) { _, _ in
                        notificationManager.toggleNotifications()
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text(permissionStatusMessage)
            }
            
            if notificationManager.isEnabled && notificationManager.permissionStatus == .authorized {
                Section {
                    if let token = notificationManager.deviceToken {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device Token")
                                .font(.headline)
                            
                            Text(token)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                            
                            Button("Copy Token") {
                                UIPasteboard.general.string = token
                                showingTokenCopied = true
                            }
                        }
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Registering for notifications...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    Button("Send Test Notification") {
                        notificationManager.sendTestNotification()
                    }
                }
            }
            
            if notificationManager.permissionStatus == .denied {
                Section {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("Notifications are disabled in iOS Settings")
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Connection Test", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Reset Instance", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetInstance()
            }
        } message: {
            Text("This will reset the current instance and may interrupt active tasks. Are you sure?")
        }
        .alert(isPresented: $showingResetSuccess) {
            if resetError.isEmpty {
                return Alert(
                    title: Text("Success"),
                    message: Text("Instance has been reset successfully."),
                    dismissButton: .default(Text("OK"))
                )
            } else {
                return Alert(
                    title: Text("Reset Failed"),
                    message: Text(resetError),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .overlay {
            if showingTokenCopied {
                Text("Token copied to clipboard")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingTokenCopied = false
                        }
                    }
            }
        }
    }
    
    private var permissionStatusMessage: String {
        switch notificationManager.permissionStatus {
        case .notDetermined:
            return "Tap to enable notifications"
        case .denied:
            return "Notifications are denied. Open iOS Settings to enable."
        case .authorized:
            return "Notifications are enabled"
        case .provisional:
            return "Provisional notifications enabled"
        case .ephemeral:
            return "Ephemeral notifications enabled"
        @unknown default:
            return ""
        }
    }
    
    private func saveAndTest() {
        let normalizedURL = normalizeURL(baseURL)
        UserDefaults.standard.set(normalizedURL, forKey: "baseURL")
        
        Task {
            do {
                let health = try await OpenCodeAPIClient.shared.getHealth()
                alertMessage = "Connected successfully!\nVersion: \(health.version)"
                showingAlert = true
            } catch {
                alertMessage = "Connection failed: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func normalizeURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        
        return normalized
    }
    
    private func resetInstance() {
        isResetting = true
        resetError = ""
        
        Task {
            do {
                try await OpenCodeAPIClient.shared.disposeInstance()
                resetError = ""
                isResetting = false
                showingResetSuccess = true
            } catch {
                resetError = "Failed to reset instance: \(error.localizedDescription)"
                isResetting = false
                showingResetSuccess = true
            }
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}