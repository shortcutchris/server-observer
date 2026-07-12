import Foundation

struct LocalServer: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case web
        case database
        case service
        case unknown

        var label: String {
            switch self {
            case .web: "Webserver"
            case .database: "Datenbank"
            case .service: "Dienst"
            case .unknown: "Unbekannt"
            }
        }

        var symbol: String {
            switch self {
            case .web: "globe"
            case .database: "cylinder.split.1x2"
            case .service: "gearshape.2"
            case .unknown: "questionmark.circle"
            }
        }
    }

    let pid: Int32
    let processName: String
    let displayName: String
    let runtime: String
    let command: String
    let workingDirectory: String?
    let ports: [Int]
    let hosts: [String]
    let kind: Kind
    let isHTTP: Bool
    let ownerUID: UInt32
    var metrics: RuntimeMetrics? = nil

    var id: Int32 { pid }
    var primaryPort: Int { ports.first ?? 0 }

    var browserURL: URL? {
        guard isHTTP, primaryPort > 0 else { return nil }
        return URL(string: "http://localhost:\(primaryPort)")
    }

    var addressLabel: String {
        guard !ports.isEmpty else { return "Kein Port" }
        if ports.count == 1 { return "localhost:\(primaryPort)" }
        return ports.map(String.init).joined(separator: ", ")
    }

    var projectPathLabel: String? {
        guard let workingDirectory else { return nil }
        return workingDirectory.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

struct ListeningEndpoint: Hashable, Sendable {
    let pid: Int32
    let processName: String
    let ownerUID: UInt32
    let host: String
    let port: Int
}
