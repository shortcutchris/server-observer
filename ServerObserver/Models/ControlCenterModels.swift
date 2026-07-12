import Foundation

struct RuntimeMetrics: Codable, Hashable, Sendable {
    var cpuPercent: Double
    var memoryBytes: UInt64
    var uptimeSeconds: TimeInterval?
    var networkInputBytes: UInt64?
    var networkOutputBytes: UInt64?
    var processCount: Int?

    var memoryLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var cpuLabel: String { String(format: "%.1f%%", cpuPercent) }

    var uptimeLabel: String? {
        guard let uptimeSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = uptimeSeconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        return formatter.string(from: uptimeSeconds)
    }

    var networkLabel: String? {
        guard let networkInputBytes, let networkOutputBytes else { return nil }
        let input = ByteCountFormatter.string(fromByteCount: Int64(networkInputBytes), countStyle: .binary)
        let output = ByteCountFormatter.string(fromByteCount: Int64(networkOutputBytes), countStyle: .binary)
        return "↓ \(input) · ↑ \(output)"
    }
}

struct ProjectProfile: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var startCommand: String
    var stopCommand: String?

    var id: String { name }
}

struct ProjectService: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var url: String
    var healthURL: String?

    var id: String { name }
    var browserURL: URL? { URL(string: url) }
    var probeURL: URL? { URL(string: healthURL ?? url) }
    var port: Int? { browserURL?.port }
}

struct ProjectRecipe: Codable, Hashable, Sendable {
    var displayName: String?
    var startCommand: String?
    var stopCommand: String?
    var restartCommand: String?
    var logCommand: String?
    var healthURL: String?
    var expectedPorts: [Int]
    var profiles: [ProjectProfile]
    var services: [ProjectService]
    var notificationsEnabled: Bool?
    var source: Source

    enum Source: String, Codable, Hashable, Sendable {
        case automatic
        case configuration
    }

    init(
        displayName: String? = nil,
        startCommand: String? = nil,
        stopCommand: String? = nil,
        restartCommand: String? = nil,
        logCommand: String? = nil,
        healthURL: String? = nil,
        expectedPorts: [Int] = [],
        profiles: [ProjectProfile] = [],
        services: [ProjectService] = [],
        notificationsEnabled: Bool? = nil,
        source: Source = .automatic
    ) {
        self.displayName = displayName
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.restartCommand = restartCommand
        self.logCommand = logCommand
        self.healthURL = healthURL
        self.expectedPorts = expectedPorts
        self.profiles = profiles
        self.services = services
        self.notificationsEnabled = notificationsEnabled
        self.source = source
    }

    var canStart: Bool { startCommand != nil || !profiles.isEmpty }

    var allExpectedPorts: [Int] {
        Array(Set(expectedPorts + services.compactMap(\.port))).sorted()
    }
}

struct GitStatus: Codable, Hashable, Sendable {
    var branch: String
    var changedFileCount: Int
    var ahead: Int
    var behind: Int
    var latestCommit: String?
    var remoteURL: String?

    var isDirty: Bool { changedFileCount > 0 }
    var summary: String {
        var parts = [branch]
        if changedFileCount > 0 { parts.append("\(changedFileCount) geändert") }
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.joined(separator: " · ")
    }
}

enum ServiceHealthState: String, Codable, Hashable, Sendable {
    case healthy
    case degraded
    case unreachable
    case unknown

    var label: String {
        switch self {
        case .healthy: "Erreichbar"
        case .degraded: "Fehlerhaft"
        case .unreachable: "Nicht erreichbar"
        case .unknown: "Ungeprüft"
        }
    }
}

struct ServiceHealth: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var url: String
    var state: ServiceHealthState
    var statusCode: Int?
    var latencyMilliseconds: Int?
    var checkedAt: Date

    var id: String { "\(name)|\(url)" }
}

struct PortConflict: Codable, Hashable, Identifiable, Sendable {
    var port: Int
    var expectedByProject: String
    var occupiedBy: String
    var ownerProjectPath: String?
    var pid: Int32?

    var id: String { "\(expectedByProject):\(port):\(occupiedBy)" }
}

struct ActivityEvent: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case started
        case stopped
        case restarted
        case unhealthy
        case recovered
        case portConflict
        case info
        case error
    }

    let id: UUID
    let date: Date
    let projectPath: String?
    let projectName: String
    let kind: Kind
    let message: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        projectPath: String?,
        projectName: String,
        kind: Kind,
        message: String
    ) {
        self.id = id
        self.date = date
        self.projectPath = projectPath
        self.projectName = projectName
        self.kind = kind
        self.message = message
    }
}

struct ProjectLogSnapshot: Hashable, Sendable {
    var text: String
    var updatedAt: Date
    var sourceLabel: String
}

enum ProjectActionState: Hashable, Sendable {
    case idle
    case starting
    case stopping
    case restarting

    var isBusy: Bool { self != .idle }
}

struct ProjectAutomationRequest: Identifiable, Hashable, Sendable {
    enum Action: String, Hashable, Sendable {
        case start
        case stop
        case restart

        var title: String {
            switch self { case .start: "starten"; case .stop: "stoppen"; case .restart: "neu starten" }
        }
    }

    let projectID: String
    let projectName: String
    let action: Action
    var id: String { "\(projectID)|\(action.rawValue)" }
}
