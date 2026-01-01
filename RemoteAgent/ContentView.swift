import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "tray")
                }

            Text("Projects View")
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }

            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    ContentView()
}
