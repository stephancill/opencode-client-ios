import SwiftUI

struct SettingsView: View {
    @State private var baseURL: String
    
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
                Button("Save") {
                    UserDefaults.standard.set(baseURL, forKey: "baseURL")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
