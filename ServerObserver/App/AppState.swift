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
    @Published var searchText = ""
    @Published var filter: Filter = .active
    @Published var selectedProjectID: String?
    @Published var serverPendingTermination: LocalServer?
    @Published var forceStopCandidate: LocalServer?
    @Published var containerPendingStop: DockerContainer?
    @Published var projectPendingStop: MonitoredProject?
    @Published var errorMessage: String?

    private let scanner = ServerScanner()
    private let projectScanner = ProjectScanner()
    private let dockerClient = DockerClient()
    private let defaults: UserDefaults
    private var descriptors: [ProjectDescriptor] = []
    private var lastProjectScan: Date?
    private var monitoringTask: Task<Void, Never>?

    private static let rootsDefaultsKey = "projectRoots.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: Self.rootsDefaultsKey),
            let savedRoots = try? JSONDecoder().decode([ProjectRoot].self, from: data)
        {
            roots = savedRoots
        } else {
            roots = []
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
        let newServers = await serverResult ?? servers
        let newDockerSnapshot = await dockerResult

        withAnimation(.snappy(duration: 0.25)) {
            servers = newServers
            containers = newDockerSnapshot.containers
            dockerState = newDockerSnapshot.state
            rebuildProjectGroups(servers: newServers, containers: newDockerSnapshot.containers)
        }
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
                containers: groupedContainers[descriptor.path] ?? []
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
            await refresh()
        }
    }

    private func stop(_ container: DockerContainer) async {
        busyContainerIDs.insert(container.id)
        defer { busyContainerIDs.remove(container.id) }
        do {
            try await dockerClient.stop(containerID: container.id)
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
            try? await Task.sleep(for: .seconds(0.8))
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stop(_ project: MonitoredProject) async {
        for server in project.servers where server.ownerUID == getuid() {
            _ = kill(server.pid, SIGTERM)
        }
        for container in project.containers where container.isRunning {
            busyContainerIDs.insert(container.id)
            do {
                try await dockerClient.stop(containerID: container.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyContainerIDs.remove(container.id)
        }
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }
}
