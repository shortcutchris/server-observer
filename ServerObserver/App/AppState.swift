import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case active
        case allProjects
        case web
        case containers
        case unassigned

        var id: Self { self }
        var title: String {
            switch self {
            case .active: "Aktiv"
            case .allProjects: "Alle Projekte"
            case .web: "Webserver"
            case .containers: "Container"
            case .unassigned: "Nicht zugeordnet"
            }
        }
    }

    @Published private(set) var roots: [ProjectRoot]
    @Published private(set) var projects: [MonitoredProject] = []
    @Published private(set) var servers: [LocalServer] = []
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var unassignedServers: [LocalServer] = []
    @Published private(set) var unassignedContainers: [DockerContainer] = []
    @Published private(set) var dockerState: DockerEngineState = .unavailable
    @Published private(set) var isScanning = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var busyContainerIDs: Set<String> = []
    @Published private(set) var busyFrontendProjectIDs: Set<String> = []
    @Published private(set) var actionStates: [String: ProjectActionState] = [:]
    @Published private(set) var activity: [ActivityEvent] = []
    @Published private(set) var projectLogs: [String: ProjectLogSnapshot] = [:]
    @Published private(set) var notificationsEnabled: Bool
    @Published var searchText = ""
    @Published var filter: Filter = .active
    @Published var selectedProjectID: String?
    @Published var serverPendingTermination: LocalServer?
    @Published var forceStopCandidate: LocalServer?
    @Published var containerPendingStop: DockerContainer?
    @Published var projectPendingStop: MonitoredProject?
    @Published var automationRequest: ProjectAutomationRequest?
    @Published var errorMessage: String?

    private let scanner = ServerScanner()
    private let projectScanner = ProjectScanner()
    private let dockerClient = DockerClient()
    private let metricsScanner = RuntimeMetricsScanner()
    private let gitInspector = GitInspector()
    private let healthCheckService = HealthCheckService()
    private let activityStore = ActivityStore()
    private let projectRunner = ProjectRunner()
    private let notificationService = NotificationService()
    private let defaults: UserDefaults
    private var descriptors: [ProjectDescriptor] = []
    private var lastProjectScan: Date?
    private var monitoringTask: Task<Void, Never>?
    private var gitStatuses: [String: GitStatus] = [:]
    private var healthStatuses: [String: [ServiceHealth]] = [:]
    private var lastEnrichment: Date?
    private var knownHealthStates: [String: ServiceHealthState] = [:]
    private var knownConflictIDs: Set<String> = []
    private var activeProfiles: [String: ProjectProfile] = [:]
    private var pendingAutomationAction: (action: ProjectAutomationRequest.Action, project: String)?

    private static let rootsDefaultsKey = "projectRoots.v1"
    private static let notificationsDefaultsKey = "notificationsEnabled.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notificationsEnabled = defaults.bool(forKey: Self.notificationsDefaultsKey)
        if
            let data = defaults.data(forKey: Self.rootsDefaultsKey),
            let savedRoots = try? JSONDecoder().decode([ProjectRoot].self, from: data)
        {
            roots = savedRoots
        } else {
            roots = []
        }
        Task { [weak self] in
            guard let self else { return }
            self.activity = await self.activityStore.load()
        }
    }

    var filteredProjects: [MonitoredProject] {
        let query = normalizedQuery
        return projects.filter { project in
            let matchesFilter: Bool = switch filter {
            case .active: project.isActive
            case .allProjects: true
            case .web: project.webCount > 0
            case .containers: !project.containers.isEmpty
            case .unassigned: false
            }
            return matchesFilter && matches(project: project, query: query)
        }
    }

    var filteredUnassignedServers: [LocalServer] {
        guard filter == .unassigned || filter == .active || filter == .web else { return [] }
        return unassignedServers.filter { server in
            (filter != .web || server.kind == .web) && matches(server: server, query: normalizedQuery)
        }
    }

    var filteredUnassignedContainers: [DockerContainer] {
        guard filter == .unassigned || filter == .active || filter == .containers || filter == .web else { return [] }
        return unassignedContainers.filter { container in
            (filter != .active || container.isActive)
                && (filter != .web || container.kind == .web)
                && matches(container: container, query: normalizedQuery)
        }
    }

    var showsUnassigned: Bool {
        !filteredUnassignedServers.isEmpty || !filteredUnassignedContainers.isEmpty
    }

    var hasVisibleContent: Bool { !filteredProjects.isEmpty || showsUnassigned }
    var webServerCount: Int {
        servers.filter { $0.kind == .web }.count
            + containers.filter { $0.kind == .web && $0.isRunning }.count
    }
    var activeContainerCount: Int { containers.filter(\.isActive).count }
    var activeProjectCount: Int { projects.filter(\.isActive).count }
    var unhealthyServiceCount: Int {
        projects.flatMap(\.serviceHealth).filter { $0.state == .degraded || $0.state == .unreachable }.count
    }
    var portConflictCount: Int { projects.flatMap(\.portConflicts).count }

    var selectedProject: MonitoredProject? {
        if let selectedProjectID, let selected = filteredProjects.first(where: { $0.id == selectedProjectID }) {
            return selected
        }
        return filteredProjects.first
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh(forceProjects: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let projectInventoryExpired = lastProjectScan.map { Date().timeIntervalSince($0) > 30 } ?? true
        if forceProjects || projectInventoryExpired {
            descriptors = await projectScanner.scan(roots: roots)
            lastProjectScan = Date()
        }

        async let serverResult = try? scanner.scan()
        async let dockerResult = dockerClient.scan(projects: descriptors)
        var newServers = await serverResult ?? servers
        let newDockerSnapshot = await dockerResult
        var newContainers = newDockerSnapshot.containers

        async let localMetricsResult = metricsScanner.scan(processIDs: newServers.map(\.pid))
        async let dockerMetricsResult = dockerClient.metrics(containerIDs: newContainers.filter(\.isActive).map(\.id))
        let localMetrics = await localMetricsResult
        let dockerMetrics = await dockerMetricsResult
        for index in newServers.indices { newServers[index].metrics = localMetrics[newServers[index].pid] }
        for index in newContainers.indices { newContainers[index].metrics = dockerMetrics[newContainers[index].id] }

        let enrichmentExpired = lastEnrichment.map { Date().timeIntervalSince($0) > 12 } ?? true
        if forceProjects || enrichmentExpired {
            gitStatuses = await gitInspector.inspect(projects: descriptors)
            lastEnrichment = Date()
        }

        withAnimation(.snappy(duration: 0.25)) {
            servers = newServers
            containers = newContainers
            dockerState = newDockerSnapshot.state
            rebuildProjectGroups(servers: newServers, containers: newContainers)
        }

        if forceProjects || enrichmentExpired {
            healthStatuses = await healthCheckService.check(projects: projects)
            applyEnrichmentAndDetectChanges()
        } else {
            applyEnrichment()
        }
        processPendingAutomationIfPossible()
        lastUpdated = Date()
    }

    func addProjectRoots(_ urls: [URL]) {
        let existing = Set(roots.map { PathUtilities.normalized($0.path) })
        let additions = urls
            .map { PathUtilities.normalized($0.path) }
            .filter { !existing.contains($0) }
            .map { ProjectRoot(path: $0) }
        guard !additions.isEmpty else { return }
        roots.append(contentsOf: additions)
        roots.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        persistRootsAndRescan()
    }

    func removeProjectRoot(_ root: ProjectRoot) {
        roots.removeAll { $0.id == root.id }
        persistRootsAndRescan()
    }

    func setProjectRoot(_ root: ProjectRoot, enabled: Bool) {
        guard let index = roots.firstIndex(where: { $0.id == root.id }) else { return }
        roots[index].isEnabled = enabled
        persistRootsAndRescan()
    }

    func setProjectRoot(_ root: ProjectRoot, scanDepth: Int) {
        guard let index = roots.firstIndex(where: { $0.id == root.id }) else { return }
        roots[index].scanDepth = min(max(scanDepth, 1), 8)
        persistRootsAndRescan()
    }

    func projectCount(for root: ProjectRoot) -> Int {
        descriptors.filter { $0.rootID == root.id }.count
    }

    func open(_ server: LocalServer) {
        guard let url = server.browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    func open(_ container: DockerContainer) {
        guard let url = container.browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ server: LocalServer) {
        guard let directory = server.workingDirectory else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
    }

    func reveal(_ project: MonitoredProject) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.descriptor.path)
    }

    func requestStop(_ server: LocalServer) {
        serverPendingTermination = server
    }

    func confirmStop() {
        guard let server = serverPendingTermination else { return }
        serverPendingTermination = nil
        Task { await stop(server, signal: SIGTERM) }
    }

    func forceStop(_ server: LocalServer) {
        forceStopCandidate = nil
        Task { await stop(server, signal: SIGKILL) }
    }

    func requestStop(_ container: DockerContainer) {
        containerPendingStop = container
    }

    func confirmContainerStop() {
        guard let container = containerPendingStop else { return }
        containerPendingStop = nil
        Task { await stop(container) }
    }

    func start(_ container: DockerContainer) {
        Task { await startContainer(container) }
    }

    func requestStop(_ project: MonitoredProject) {
        projectPendingStop = project
    }

    func confirmProjectStop() {
        guard let project = projectPendingStop else { return }
        projectPendingStop = nil
        Task { await stop(project) }
    }

    func start(_ project: MonitoredProject, profile: ProjectProfile? = nil) {
        Task { _ = await startProject(project, profile: profile) }
    }

    func restart(_ project: MonitoredProject) {
        Task { await restartProject(project) }
    }

    func openFrontend(_ project: MonitoredProject, target: ProjectBrowserTarget? = nil) {
        let selectedTarget = target ?? project.primaryBrowserTarget

        if project.isActive, let selectedTarget {
            NSWorkspace.shared.open(selectedTarget.url)
            Task {
                await record(
                    project: project,
                    kind: .info,
                    message: "Frontend \(selectedTarget.name) geöffnet"
                )
            }
            return
        }

        guard project.descriptor.recipe.canStart else {
            if let selectedTarget {
                NSWorkspace.shared.open(selectedTarget.url)
            } else {
                errorMessage = "Für \(project.descriptor.name) wurde noch kein Frontend erkannt oder konfiguriert."
            }
            return
        }

        Task {
            busyFrontendProjectIDs.insert(project.id)
            defer { busyFrontendProjectIDs.remove(project.id) }
            guard await startProject(project, profile: nil) else { return }
            await waitForFrontend(projectID: project.id, preferredTarget: selectedTarget)
        }
    }

    func loadLogs(for project: MonitoredProject) {
        Task {
            projectLogs[project.id] = await projectRunner.logSnapshot(
                for: project.descriptor,
                command: project.descriptor.recipe.logCommand
            )
        }
    }

    func clearActivity() {
        activity = []
        Task { await activityStore.clear() }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        Task {
            let authorized = enabled ? await notificationService.requestAuthorization() : false
            notificationsEnabled = enabled && authorized
            defaults.set(notificationsEnabled, forKey: Self.notificationsDefaultsKey)
            if enabled && !authorized {
                errorMessage = "Mitteilungen wurden in den macOS-Systemeinstellungen nicht erlaubt."
            }
        }
    }

    func installCLI() {
        do {
            guard let source = Bundle.main.url(forResource: "server-observer", withExtension: "sh") else {
                throw CLIInstallError.resourceMissing
            }
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("server-observer")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            Task { await record(project: nil, kind: .info, message: "CLI nach ~/.local/bin/server-observer installiert") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "serverobserver" else { return }
        let action = url.host ?? url.pathComponents.dropFirst().first ?? "open"
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems?.first(where: { $0.name == "project" })?.value
        switch action {
        case "refresh": Task { await refresh(forceProjects: true) }
        case "start": queueOrRequestAutomation(.start, project: query)
        case "restart": queueOrRequestAutomation(.restart, project: query)
        case "stop": queueOrRequestAutomation(.stop, project: query)
        default: break
        }
    }

    func confirmAutomation() {
        guard
            let request = automationRequest,
            let project = projects.first(where: { $0.id == request.projectID })
        else {
            automationRequest = nil
            return
        }
        automationRequest = nil
        switch request.action {
        case .start: start(project)
        case .restart: restart(project)
        case .stop: requestStop(project)
        }
    }

    private func requestAutomation(_ action: ProjectAutomationRequest.Action, for project: MonitoredProject) {
        automationRequest = ProjectAutomationRequest(
            projectID: project.id,
            projectName: project.descriptor.name,
            action: action
        )
    }

    private func queueOrRequestAutomation(_ action: ProjectAutomationRequest.Action, project value: String?) {
        guard let value, !value.isEmpty else {
            errorMessage = "Für die externe Aktion fehlt ein Projektname oder Pfad."
            return
        }
        if let project = resolveProject(value) {
            requestAutomation(action, for: project)
        } else if isScanning || projects.isEmpty {
            pendingAutomationAction = (action, value)
        } else {
            errorMessage = "Das Projekt „\(value)“ wurde in den überwachten Ordnern nicht gefunden."
        }
    }

    private func processPendingAutomationIfPossible() {
        guard let pending = pendingAutomationAction else { return }
        pendingAutomationAction = nil
        if let project = resolveProject(pending.project) {
            requestAutomation(pending.action, for: project)
        } else {
            errorMessage = "Das Projekt „\(pending.project)“ wurde in den überwachten Ordnern nicht gefunden."
        }
    }

    private func resolveProject(_ value: String) -> MonitoredProject? {
        projects.first {
            $0.id == value || $0.descriptor.name.localizedCaseInsensitiveCompare(value) == .orderedSame
        }
    }

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(project: MonitoredProject, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let projectValues = [project.descriptor.name, project.descriptor.path]
        return projectValues.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            || project.servers.contains(where: { matches(server: $0, query: query) })
            || project.containers.contains(where: { matches(container: $0, query: query) })
    }

    private func matches(server: LocalServer, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [server.displayName, server.runtime, server.command, server.addressLabel]
            .contains(where: { $0.localizedCaseInsensitiveContains(query) })
    }

    private func matches(container: DockerContainer, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [container.displayName, container.name, container.image, container.portsLabel]
            .contains(where: { $0.localizedCaseInsensitiveContains(query) })
    }

    private func persistRootsAndRescan() {
        if let data = try? JSONEncoder().encode(roots) {
            defaults.set(data, forKey: Self.rootsDefaultsKey)
        }
        lastProjectScan = nil
        Task { await refresh(forceProjects: true) }
    }

    private func rebuildProjectGroups(servers: [LocalServer], containers: [DockerContainer]) {
        var groupedServers: [String: [LocalServer]] = [:]
        var unassignedServers: [LocalServer] = []
        for server in servers {
            if let path = ProjectAssociation.projectPath(for: server.workingDirectory, projects: descriptors) {
                groupedServers[path, default: []].append(server)
            } else {
                unassignedServers.append(server)
            }
        }

        var groupedContainers: [String: [DockerContainer]] = [:]
        var unassignedContainers: [DockerContainer] = []
        for container in containers {
            if let path = container.projectPath, descriptors.contains(where: { $0.path == path }) {
                groupedContainers[path, default: []].append(container)
            } else {
                unassignedContainers.append(container)
            }
        }

        projects = descriptors.map { descriptor in
            MonitoredProject(
                descriptor: descriptor,
                servers: (groupedServers[descriptor.path] ?? []).sorted { $0.primaryPort < $1.primaryPort },
                containers: groupedContainers[descriptor.path] ?? [],
                gitStatus: gitStatuses[descriptor.path],
                serviceHealth: healthStatuses[descriptor.path] ?? []
            )
        }
        self.unassignedServers = unassignedServers
        self.unassignedContainers = unassignedContainers

        if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }
    }

    private func stop(_ server: LocalServer, signal: Int32) async {
        guard server.ownerUID == getuid() else {
            errorMessage = "Dieser Prozess gehört einem anderen Benutzer und kann nicht beendet werden."
            return
        }

        guard kill(server.pid, signal) == 0 else {
            errorMessage = String(cString: strerror(errno))
            return
        }

        try? await Task.sleep(for: .seconds(signal == SIGTERM ? 1.5 : 0.4))
        if kill(server.pid, 0) == 0 {
            if signal == SIGTERM { forceStopCandidate = server }
        } else {
            await record(
                project: project(containing: server),
                kind: .stopped,
                message: "\(server.displayName) auf Port \(server.primaryPort) gestoppt"
            )
            await refresh()
        }
    }

    private func stop(_ container: DockerContainer) async {
        busyContainerIDs.insert(container.id)
        defer { busyContainerIDs.remove(container.id) }
        do {
            try await dockerClient.stop(containerID: container.id)
            await record(
                project: project(containing: container),
                kind: .stopped,
                message: "Container \(container.displayName) gestoppt"
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startContainer(_ container: DockerContainer) async {
        busyContainerIDs.insert(container.id)
        defer { busyContainerIDs.remove(container.id) }
        do {
            try await dockerClient.start(containerID: container.id)
            await record(
                project: project(containing: container),
                kind: .started,
                message: "Container \(container.displayName) gestartet"
            )
            try? await Task.sleep(for: .seconds(0.8))
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stop(_ project: MonitoredProject) async {
        actionStates[project.id] = .stopping
        defer { actionStates[project.id] = .idle }
        do {
            if let command = activeProfiles[project.id]?.stopCommand ?? project.descriptor.recipe.stopCommand {
                try await projectRunner.runAndWait(command: command, project: project.descriptor, action: "Stop")
            } else {
                for server in project.servers where server.ownerUID == getuid() {
                    _ = kill(server.pid, SIGTERM)
                }
                for container in project.containers where container.isRunning {
                    busyContainerIDs.insert(container.id)
                    try await dockerClient.stop(containerID: container.id)
                    busyContainerIDs.remove(container.id)
                }
            }
            activeProfiles.removeValue(forKey: project.id)
            await record(project: project, kind: .stopped, message: "Projekt gestoppt")
        } catch {
            busyContainerIDs.subtract(project.containers.map(\.id))
            await report(error, project: project, action: "Stoppen")
        }
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    private func startProject(_ project: MonitoredProject, profile: ProjectProfile?) async -> Bool {
        let command = profile?.startCommand ?? project.descriptor.recipe.startCommand
        guard let command else {
            errorMessage = "Für \(project.descriptor.name) wurde kein Startbefehl erkannt. Lege ihn in .server-observer.yml fest."
            return false
        }
        actionStates[project.id] = .starting
        defer { actionStates[project.id] = .idle }
        do {
            if let profile { activeProfiles[project.id] = profile }
            _ = try await projectRunner.run(
                command: command,
                project: project.descriptor,
                action: profile.map { "Profil \($0.name) starten" } ?? "Start"
            )
            await record(
                project: project,
                kind: .started,
                message: profile.map { "Profil \($0.name) gestartet" } ?? "Projekt gestartet"
            )
            try? await Task.sleep(for: .seconds(1.2))
            await refresh()
            return true
        } catch {
            await report(error, project: project, action: "Starten")
            return false
        }
    }

    private func waitForFrontend(projectID: String, preferredTarget: ProjectBrowserTarget?) async {
        let deadline = Date().addingTimeInterval(30)
        var lastRefresh = Date.distantPast

        while Date() < deadline {
            if Date().timeIntervalSince(lastRefresh) >= 2 {
                await refresh()
                lastRefresh = Date()
            }

            guard let project = projects.first(where: { $0.id == projectID }) else { break }
            let target = preferredTarget ?? project.primaryBrowserTarget
            if let target, await frontendResponds(at: target.url) {
                NSWorkspace.shared.open(target.url)
                await record(project: project, kind: .info, message: "Frontend \(target.name) gestartet und geöffnet")
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
        }

        errorMessage = "Das Frontend hat innerhalb von 30 Sekunden noch nicht geantwortet. Prüfe Startbefehl, URL und Logs."
    }

    private func frontendResponds(at url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 0.9
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 405 || http.statusCode == 501 {
                request.httpMethod = "GET"
                let (_, fallback) = try await URLSession.shared.data(for: request)
                return fallback is HTTPURLResponse
            }
            return true
        } catch {
            return false
        }
    }

    private func restartProject(_ project: MonitoredProject) async {
        actionStates[project.id] = .restarting
        defer { actionStates[project.id] = .idle }
        do {
            if let profile = activeProfiles[project.id] {
                if let stopCommand = profile.stopCommand {
                    try await projectRunner.runAndWait(command: stopCommand, project: project.descriptor, action: "Profil-Neustart – Stop")
                }
                _ = try await projectRunner.run(command: profile.startCommand, project: project.descriptor, action: "Profil-Neustart – Start")
            } else if let command = project.descriptor.recipe.restartCommand {
                try await projectRunner.runAndWait(command: command, project: project.descriptor, action: "Neustart")
            } else {
                if let stopCommand = project.descriptor.recipe.stopCommand {
                    try await projectRunner.runAndWait(command: stopCommand, project: project.descriptor, action: "Neustart – Stop")
                } else {
                    for server in project.servers where server.ownerUID == getuid() { _ = kill(server.pid, SIGTERM) }
                    for container in project.containers where container.isRunning {
                        try await dockerClient.stop(containerID: container.id)
                    }
                }
                guard let startCommand = project.descriptor.recipe.startCommand else {
                    throw ProjectActionError.noStartCommand
                }
                _ = try await projectRunner.run(command: startCommand, project: project.descriptor, action: "Neustart – Start")
            }
            await record(project: project, kind: .restarted, message: "Projekt neu gestartet")
            try? await Task.sleep(for: .seconds(1.2))
            await refresh()
        } catch {
            await report(error, project: project, action: "Neustarten")
        }
    }

    private func applyEnrichment() {
        let conflicts = PortConflictDetector.detect(
            projects: projects,
            unassignedServers: unassignedServers,
            unassignedContainers: unassignedContainers
        )
        projects = projects.map { project in
            var updated = project
            updated.gitStatus = gitStatuses[project.id]
            updated.serviceHealth = healthStatuses[project.id] ?? []
            updated.portConflicts = conflicts[project.id] ?? []
            return updated
        }
    }

    private func applyEnrichmentAndDetectChanges() {
        applyEnrichment()
        let newConflicts = Set(projects.flatMap(\.portConflicts).map(\.id))
        for project in projects {
            for conflict in project.portConflicts where !knownConflictIDs.contains(conflict.id) {
                Task {
                    await record(
                        project: project,
                        kind: .portConflict,
                        message: "Port \(conflict.port) wird bereits von \(conflict.occupiedBy) belegt",
                        notify: true
                    )
                }
            }
            for health in project.serviceHealth {
                let key = "\(project.id)|\(health.id)"
                let previous = knownHealthStates[key]
                knownHealthStates[key] = health.state
                guard let previous, previous != health.state else { continue }
                if health.state == .healthy && previous != .healthy {
                    Task { await record(project: project, kind: .recovered, message: "\(health.name) ist wieder erreichbar", notify: true) }
                } else if health.state == .unreachable || health.state == .degraded {
                    Task { await record(project: project, kind: .unhealthy, message: "\(health.name): \(health.state.label)", notify: true) }
                }
            }
        }
        knownConflictIDs = newConflicts
    }

    private func project(containing server: LocalServer) -> MonitoredProject? {
        projects.first { $0.servers.contains(where: { $0.id == server.id }) }
    }

    private func project(containing container: DockerContainer) -> MonitoredProject? {
        projects.first { $0.containers.contains(where: { $0.id == container.id }) }
    }

    private func record(
        project: MonitoredProject?,
        kind: ActivityEvent.Kind,
        message: String,
        notify: Bool = false
    ) async {
        let event = ActivityEvent(
            projectPath: project?.id,
            projectName: project?.descriptor.name ?? "Server Observer",
            kind: kind,
            message: message
        )
        activity = await activityStore.append(event, to: activity)
        let projectNotifications = project?.descriptor.recipe.notificationsEnabled ?? true
        if notify && notificationsEnabled && projectNotifications {
            await notificationService.send(title: event.projectName, body: message)
        }
    }

    private func report(_ error: Error, project: MonitoredProject, action: String) async {
        errorMessage = error.localizedDescription
        await record(project: project, kind: .error, message: "\(action) fehlgeschlagen: \(error.localizedDescription)")
    }
}

private enum ProjectActionError: LocalizedError {
    case noStartCommand
    var errorDescription: String? { "Kein Startbefehl konfiguriert." }
}

private enum CLIInstallError: LocalizedError {
    case resourceMissing
    var errorDescription: String? { "Die CLI-Datei ist nicht im App-Bundle enthalten." }
}
