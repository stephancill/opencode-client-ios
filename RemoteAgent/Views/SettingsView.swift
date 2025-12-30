import SwiftUI
import Foundation

struct SettingsView: View {
    @State private var baseURL: String
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
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
            }
        }
        .navigationTitle("Settings")
        .alert("Connection Test", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
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
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
