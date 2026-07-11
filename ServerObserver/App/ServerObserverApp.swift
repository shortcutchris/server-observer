import SwiftUI

@main
struct ServerObserverApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updateController = UpdateController()

    var body: some Scene {
        Window("Server Observer", id: "main") {
            ServerDashboardView()
                .environmentObject(appState)
                .environmentObject(updateController)
        }
        .defaultSize(width: 470, height: 580)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
                .environmentObject(updateController)
        } label: {
            Label("Server Observer", systemImage: appState.webServerCount > 0 ? "dot.radiowaves.left.and.right" : "circle.dotted")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            UpdateSettingsView()
                .environmentObject(updateController)
                .frame(width: 420)
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateController: UpdateController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(appState.webServerCount) Webserver aktiv")
        Divider()
        ForEach(appState.servers.filter { $0.kind == .web }.prefix(6)) { server in
            Button("\(server.displayName) – :\(server.primaryPort)") {
                appState.open(server)
            }
        }
        if appState.webServerCount == 0 {
            Text("Keine Webserver gefunden")
        }
        Divider()
        Button("Panel öffnen") { openWindow(id: "main") }
        Button("Jetzt aktualisieren") { Task { await appState.refresh() } }
        Button("Nach App-Updates suchen …") { updateController.checkForUpdates() }
            .disabled(!updateController.canCheckForUpdates)
        Divider()
        Button("Server Observer beenden") { NSApplication.shared.terminate(nil) }
    }
}

private struct UpdateSettingsView: View {
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Server Observer")
                        .font(.title2.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Server Observer prüft automatisch den signierten Release-Feed auf neue Versionen.")
                .foregroundStyle(.secondary)

            Button("Nach Updates suchen …") {
                updateController.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!updateController.canCheckForUpdates)
        }
        .padding(24)
    }
}
