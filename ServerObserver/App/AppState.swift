import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case web
        case all
        case services

        var id: Self { self }
        var title: String {
            switch self {
            case .web: "Webserver"
            case .all: "Alle"
            case .services: "Dienste"
            }
        }
    }

    @Published private(set) var servers: [LocalServer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastUpdated: Date?
    @Published var searchText = ""
    @Published var filter: Filter = .web
    @Published var selectedServerID: LocalServer.ID?
    @Published var serverPendingTermination: LocalServer?
    @Published var forceStopCandidate: LocalServer?
    @Published var errorMessage: String?

    private let scanner = ServerScanner()
    private var monitoringTask: Task<Void, Never>?

    var filteredServers: [LocalServer] {
        servers.filter { server in
            let matchesFilter: Bool = switch filter {
            case .web: server.kind == .web
            case .all: true
            case .services: !server.isHTTP
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || [
                server.displayName,
                server.runtime,
                server.command,
                server.addressLabel,
                server.projectPathLabel ?? ""
            ].contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesFilter && matchesSearch
        }
    }

    var webServerCount: Int { servers.filter { $0.kind == .web }.count }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            let newServers = try await scanner.scan()
            withAnimation(.snappy(duration: 0.25)) {
                servers = newServers
            }
            if let selectedServerID, !newServers.contains(where: { $0.id == selectedServerID }) {
                self.selectedServerID = nil
            }
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ server: LocalServer) {
        guard let url = server.browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ server: LocalServer) {
        guard let directory = server.workingDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory)])
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
}
