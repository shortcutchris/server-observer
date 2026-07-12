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
                .onOpenURL { appState.handleURL($0) }
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
            AppSettingsView()
                .environmentObject(appState)
                .environmentObject(updateController)
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateController: UpdateController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("\(appState.activeProjectCount) Projekte · \(appState.activeContainerCount) Container · \(appState.servers.count) Prozesse")
        Divider()
        ForEach(appState.projects.filter(\.isActive).prefix(6)) { project in
            Menu(project.descriptor.name) {
                ForEach(project.servers.prefix(6)) { server in
                    Button("\(server.displayName) – :\(server.primaryPort)") {
                        appState.open(server)
                    }
                    .disabled(server.browserURL == nil)
                }
                ForEach(project.containers.filter(\.isActive).prefix(6)) { container in
                    Button("\(container.displayName) – \(container.portsLabel)") {
                        appState.open(container)
                    }
                    .disabled(container.browserURL == nil)
                }
                Divider()
                if project.browserTargets.count > 1 {
                    Menu("Frontend öffnen") {
                        ForEach(project.browserTargets) { target in
                            Button("\(target.name) – \(target.addressLabel)") {
                                appState.openFrontend(project, target: target)
                            }
                        }
                    }
                } else if project.primaryBrowserTarget != nil {
                    Button("Frontend öffnen") { appState.openFrontend(project) }
                }
                if project.descriptor.recipe.canStart {
                    Button("Neu starten") { appState.restart(project) }
                }
                Button("Projekt stoppen", role: .destructive) { appState.requestStop(project) }
            }
        }
        if appState.activeProjectCount == 0 {
            Text("Keine aktiven Projekte")
        }
        let startable = appState.projects.filter { !$0.isActive && $0.descriptor.recipe.canStart }
        if !startable.isEmpty {
            Menu("Projekt starten") {
                ForEach(startable.prefix(12)) { project in
                    Button(project.descriptor.name) { appState.start(project) }
                }
            }
        }
        if appState.unhealthyServiceCount > 0 || appState.portConflictCount > 0 {
            Divider()
            Text("\(appState.unhealthyServiceCount) Health-Fehler · \(appState.portConflictCount) Portkonflikte")
        }
        Divider()
        Button("Panel öffnen") { openWindow(id: "main") }
        Button("Projektordner …") { openSettings() }
        Button("Jetzt aktualisieren") { Task { await appState.refresh() } }
        Button("Nach App-Updates suchen …") { updateController.checkForUpdates() }
            .disabled(!updateController.canCheckForUpdates)
        Divider()
        Button("Server Observer beenden") { NSApplication.shared.terminate(nil) }
    }
}
