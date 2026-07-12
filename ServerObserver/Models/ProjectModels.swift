import Darwin
import Foundation

struct ProjectRoot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var path: String
    var isEnabled: Bool
    var scanDepth: Int

    init(id: UUID = UUID(), path: String, isEnabled: Bool = true, scanDepth: Int = 4) {
        self.id = id
        self.path = PathUtilities.normalized(path)
        self.isEnabled = isEnabled
        self.scanDepth = min(max(scanDepth, 1), 8)
    }

    var displayPath: String { PathUtilities.abbreviateHome(path) }
}

enum ProjectMarker: String, Codable, Hashable, Sendable, CaseIterable {
    case git
    case compose
    case devContainer
    case dockerfile
    case node
    case python
    case swift
    case go
    case rust
    case java

    var label: String {
        switch self {
        case .git: "Git"
        case .compose: "Compose"
        case .devContainer: "Dev Container"
        case .dockerfile: "Docker"
        case .node: "Node.js"
        case .python: "Python"
        case .swift: "Swift"
        case .go: "Go"
        case .rust: "Rust"
        case .java: "Java"
        }
    }

    var isStrongProjectBoundary: Bool {
        self == .git || self == .compose || self == .devContainer
    }
}

struct ProjectDescriptor: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let rootID: UUID
    let markers: Set<ProjectMarker>
    let recipe: ProjectRecipe

    init(
        path: String,
        name: String,
        rootID: UUID,
        markers: Set<ProjectMarker>,
        recipe: ProjectRecipe = ProjectRecipe()
    ) {
        self.path = path
        self.name = name
        self.rootID = rootID
        self.markers = markers
        self.recipe = recipe
    }

    var id: String { path }
    var displayPath: String { PathUtilities.abbreviateHome(path) }
    var hasCompose: Bool { markers.contains(.compose) }
    var hasDevContainer: Bool { markers.contains(.devContainer) }
}

enum DockerHealth: String, Codable, Hashable, Sendable {
    case healthy
    case unhealthy
    case starting
    case none

    var label: String {
        switch self {
        case .healthy: "Healthy"
        case .unhealthy: "Unhealthy"
        case .starting: "Startet"
        case .none: "Kein Healthcheck"
        }
    }
}

enum DockerContainerKind: String, Hashable, Sendable {
    case web
    case database
    case worker

    var label: String {
        switch self {
        case .web: "Container-Webserver"
        case .database: "Container-Datenbank"
        case .worker: "Container"
        }
    }
}

struct DockerPort: Hashable, Sendable {
    let containerPort: Int
    let protocolName: String
    let hostIP: String?
    let hostPort: Int?

    var isPublished: Bool { hostPort != nil }

    var displayLabel: String {
        if let hostPort {
            return "localhost:\(hostPort) → \(containerPort)/\(protocolName)"
        }
        return "intern:\(containerPort)/\(protocolName)"
    }
}

struct DockerMount: Hashable, Sendable {
    let source: String
    let destination: String
    let type: String
}

struct DockerContainer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let image: String
    let state: String
    let health: DockerHealth
    let ports: [DockerPort]
    let mounts: [DockerMount]
    let composeProject: String?
    let composeService: String?
    let projectPath: String?
    let kind: DockerContainerKind
    let httpPort: Int?
    var metrics: RuntimeMetrics? = nil

    var displayName: String { composeService ?? name }
    var isRunning: Bool { state == "running" || state == "restarting" }
    var isActive: Bool { isRunning || state == "paused" }
    var browserURL: URL? {
        guard let httpPort else { return nil }
        return URL(string: "http://localhost:\(httpPort)")
    }

    var portsLabel: String {
        guard !ports.isEmpty else { return "Keine Ports" }
        return ports.prefix(3).map(\.displayLabel).joined(separator: " · ")
    }
}

enum DockerEngineState: Hashable, Sendable {
    case ready(version: String)
    case stopped
    case unavailable

    var label: String {
        switch self {
        case let .ready(version): "Docker \(version)"
        case .stopped: "Docker ist nicht gestartet"
        case .unavailable: "Docker CLI nicht gefunden"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

struct DockerSnapshot: Sendable {
    let state: DockerEngineState
    let containers: [DockerContainer]
}

struct MonitoredProject: Identifiable, Hashable, Sendable {
    let descriptor: ProjectDescriptor
    let servers: [LocalServer]
    let containers: [DockerContainer]
    var gitStatus: GitStatus? = nil
    var serviceHealth: [ServiceHealth] = []
    var portConflicts: [PortConflict] = []

    var id: String { descriptor.id }
    var isActive: Bool { !servers.isEmpty || containers.contains(where: \.isActive) }
    var activeRuntimeCount: Int { servers.count + containers.filter(\.isActive).count }
    var webCount: Int {
        servers.filter { $0.kind == .web }.count + containers.filter { $0.kind == .web && $0.isRunning }.count
    }

    var browserTargets: [ProjectBrowserTarget] {
        let configured = descriptor.recipe.services.compactMap { service -> ProjectBrowserTarget? in
            guard let url = service.browserURL else { return nil }
            return ProjectBrowserTarget(
                name: service.name,
                url: url,
                source: .configuration,
                isPreferred: service.isFrontend == true
            )
        }
        let local = servers.compactMap { server -> ProjectBrowserTarget? in
            guard let url = server.browserURL else { return nil }
            return ProjectBrowserTarget(
                name: server.displayName,
                url: url,
                source: .localProcess,
                isPreferred: false
            )
        }
        let docker = containers.compactMap { container -> ProjectBrowserTarget? in
            guard let url = container.browserURL else { return nil }
            return ProjectBrowserTarget(
                name: container.displayName,
                url: url,
                source: .docker,
                isPreferred: false
            )
        }

        var seen = Set<String>()
        return (configured.sorted { $0.isPreferred && !$1.isPreferred } + local + docker).filter {
            seen.insert($0.normalizedURL).inserted
        }
    }

    var primaryBrowserTarget: ProjectBrowserTarget? {
        browserTargets.first(where: \.isPreferred) ?? browserTargets.first
    }
}

enum PathUtilities {
    static func normalized(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if standardized.withCString({ realpath($0, &buffer) }) != nil {
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
        return standardized
    }

    static func isPath(_ path: String, inside parent: String) -> Bool {
        let child = normalized(path)
        let root = normalized(parent)
        return child == root || child.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

enum ProjectAssociation {
    static func projectPath(for path: String?, projects: [ProjectDescriptor]) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return projects
            .filter { PathUtilities.isPath(path, inside: $0.path) }
            .max { $0.path.count < $1.path.count }?
            .path
    }
}
