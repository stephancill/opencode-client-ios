import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "tray")
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
