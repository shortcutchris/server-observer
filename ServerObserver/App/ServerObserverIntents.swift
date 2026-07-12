import AppIntents
import AppKit

struct RefreshServerObserverIntent: AppIntent {
    static let title: LocalizedStringResource = "Server Observer aktualisieren"
    static let description = IntentDescription("Scannt Projekte, Ports, Prozesse, Container und Healthchecks neu.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        NSWorkspace.shared.open(URL(string: "serverobserver://refresh")!)
        return .result()
    }
}

struct StartServerObserverProjectIntent: AppIntent {
    static let title: LocalizedStringResource = "Projekt starten"
    static let openAppWhenRun = true
    @Parameter(title: "Projektname oder Pfad") var project: String

    func perform() async throws -> some IntentResult {
        open(action: "start", project: project)
        return .result()
    }
}

struct StopServerObserverProjectIntent: AppIntent {
    static let title: LocalizedStringResource = "Projekt stoppen"
    static let openAppWhenRun = true
    @Parameter(title: "Projektname oder Pfad") var project: String

    func perform() async throws -> some IntentResult {
        open(action: "stop", project: project)
        return .result()
    }
}

struct RestartServerObserverProjectIntent: AppIntent {
    static let title: LocalizedStringResource = "Projekt neu starten"
    static let openAppWhenRun = true
    @Parameter(title: "Projektname oder Pfad") var project: String

    func perform() async throws -> some IntentResult {
        open(action: "restart", project: project)
        return .result()
    }
}

private func open(action: String, project: String) {
    var components = URLComponents()
    components.scheme = "serverobserver"
    components.host = action
    components.queryItems = [URLQueryItem(name: "project", value: project)]
    if let url = components.url { NSWorkspace.shared.open(url) }
}

struct ServerObserverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RefreshServerObserverIntent(), phrases: ["Aktualisiere \(.applicationName)"], shortTitle: "Server aktualisieren", systemImageName: "arrow.clockwise")
        AppShortcut(intent: StartServerObserverProjectIntent(), phrases: ["Starte ein Projekt mit \(.applicationName)"], shortTitle: "Projekt starten", systemImageName: "play.fill")
        AppShortcut(intent: StopServerObserverProjectIntent(), phrases: ["Stoppe ein Projekt mit \(.applicationName)"], shortTitle: "Projekt stoppen", systemImageName: "stop.fill")
        AppShortcut(intent: RestartServerObserverProjectIntent(), phrases: ["Starte ein Projekt mit \(.applicationName) neu"], shortTitle: "Projekt neu starten", systemImageName: "arrow.clockwise")
    }
}
