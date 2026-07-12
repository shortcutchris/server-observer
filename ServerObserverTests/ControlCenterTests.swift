import Foundation
import XCTest
@testable import ServerObserver

final class ControlCenterTests: XCTestCase {
    func testParsesProjectConfigurationWithProfilesAndServices() {
        let recipe = ProjectRecipeLoader.parseYAML(
            """
            name: Acme Control Center
            start: pnpm dev
            stop: pkill -f acme-dev
            restart: pnpm restart
            logs: tail -f logs/dev.log
            ports: [3000, 5432, 3000]
            notifications: false
            profiles:
              Web only:
                start: pnpm dev:web
                stop: pnpm stop:web
              Full stack:
                start: docker compose up -d
            services:
              Frontend:
                url: http://localhost:3000/#ready
                health: http://localhost:3000/api/health
              Database UI:
                url: http://localhost:8080
            """
        )

        XCTAssertEqual(recipe.displayName, "Acme Control Center")
        XCTAssertEqual(recipe.startCommand, "pnpm dev")
        XCTAssertEqual(recipe.expectedPorts, [3000, 5432])
        XCTAssertEqual(recipe.notificationsEnabled, false)
        XCTAssertEqual(recipe.profiles.map(\.name), ["Web only", "Full stack"])
        XCTAssertEqual(recipe.services.first?.url, "http://localhost:3000/#ready")
        XCTAssertEqual(recipe.services.last?.port, 8080)
        XCTAssertEqual(recipe.source, .configuration)
    }

    func testParsesProcessAndNetworkMetrics() {
        let ps = RuntimeMetricsScanner.parsePS("  123  12.5  2048  01:02:03\n 456 0.0 512 2-03:04:05\n")
        XCTAssertEqual(ps[123]?.cpuPercent, 12.5)
        XCTAssertEqual(ps[123]?.memoryBytes, 2_097_152)
        XCTAssertEqual(ps[123]?.uptimeSeconds, 3_723)
        XCTAssertEqual(ps[456]?.uptimeSeconds, 183_845)

        let nettop = RuntimeMetricsScanner.parseNettop(
            "time,,bytes_in,bytes_out,\n12:00,node.123,5000,9000,\n"
        )
        XCTAssertEqual(nettop[123]?.input, 5_000)
        XCTAssertEqual(nettop[123]?.output, 9_000)
    }

    func testParsesDockerStats() {
        let id = "1234567890abcdef"
        let output = #"{"ID":"1234567890ab","CPUPerc":"1.25%","MemUsage":"12.5MiB / 1GiB","NetIO":"3.2kB / 4.5MB","PIDs":"7"}"#
        let metrics = DockerClient.parseStats(output, requestedIDs: [id])[id]
        XCTAssertEqual(metrics?.cpuPercent, 1.25)
        XCTAssertEqual(metrics?.memoryBytes, 13_107_200)
        XCTAssertEqual(metrics?.networkInputBytes, 3_200)
        XCTAssertEqual(metrics?.networkOutputBytes, 4_500_000)
        XCTAssertEqual(metrics?.processCount, 7)
    }

    func testParsesGitStatus() {
        let value = GitInspector.parse(
            "## feature/control...origin/feature/control [ahead 2, behind 1]\n M App.swift\n?? New.swift\n",
            latestCommit: "abc123 Add dashboard",
            remoteURL: "git@github.com:acme/app.git"
        )
        XCTAssertEqual(value?.branch, "feature/control")
        XCTAssertEqual(value?.changedFileCount, 2)
        XCTAssertEqual(value?.ahead, 2)
        XCTAssertEqual(value?.behind, 1)
    }

    func testDetectsPortOccupiedByUnassignedProcess() {
        let descriptor = ProjectDescriptor(
            path: "/tmp/acme",
            name: "Acme",
            rootID: UUID(),
            markers: [.node],
            recipe: ProjectRecipe(expectedPorts: [3000])
        )
        let project = MonitoredProject(descriptor: descriptor, servers: [], containers: [])
        let server = LocalServer(
            pid: 42,
            processName: "node",
            displayName: "Other Vite",
            runtime: "Node.js",
            command: "vite",
            workingDirectory: "/outside",
            ports: [3000],
            hosts: ["127.0.0.1"],
            kind: .web,
            isHTTP: true,
            ownerUID: 501
        )

        let conflicts = PortConflictDetector.detect(projects: [project], unassignedServers: [server])
        XCTAssertEqual(conflicts[descriptor.path]?.first?.port, 3000)
        XCTAssertEqual(conflicts[descriptor.path]?.first?.pid, 42)
    }

    func testActivityStorePersistsAndClears() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID()).json")
        let store = ActivityStore(fileURL: url)
        let event = ActivityEvent(projectPath: "/tmp/acme", projectName: "Acme", kind: .started, message: "Gestartet")
        let saved = await store.append(event, to: [])
        XCTAssertEqual(saved.count, 1)
        let loaded = await store.load()
        XCTAssertEqual(loaded.first?.message, "Gestartet")
        await store.clear()
        let cleared = await store.load()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testProjectRunnerExecutesIsolatedCommandAndCapturesLog() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        let descriptor = ProjectDescriptor(path: path.path, name: "Runner Test", rootID: UUID(), markers: [.swift])
        let runner = ProjectRunner()

        try await runner.runAndWait(command: "printf 'isolated-run-ok\\n'", project: descriptor, action: "Test")
        let log = await runner.logSnapshot(for: descriptor, command: nil)

        XCTAssertTrue(log.text.contains("isolated-run-ok"))
        XCTAssertEqual(log.sourceLabel, "Server Observer Log")
    }
}
