import Foundation

actor ProjectRunner {
    private var processes: [String: Process] = [:]
    private let logDirectory: URL

    init() {
        logDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ServerObserver/logs", isDirectory: true)
    }

    func run(command: String, project: ProjectDescriptor, action: String) async throws -> Int32 {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logURL = logURL(for: project)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        handle.write(Data("\n\n[\(Date().formatted())] \(action): \(command)\n".utf8))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path, isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self] finished in
            try? handle.close()
            Task { await self?.forget(projectID: project.id, pid: finished.processIdentifier) }
        }
        processes[project.id] = process
        do {
            try process.run()
        } catch {
            processes.removeValue(forKey: project.id)
            try? handle.close()
            throw error
        }
        return process.processIdentifier
    }

    func runAndWait(command: String, project: ProjectDescriptor, action: String) async throws {
        let pid = try await run(command: command, project: project, action: action)
        while processes[project.id]?.processIdentifier == pid {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func logSnapshot(for project: ProjectDescriptor, command: String?) async -> ProjectLogSnapshot {
        if let command, !command.isEmpty {
            do {
                let output = try await CommandRunner.run(
                    "/bin/zsh",
                    arguments: ["-lc", "cd \(Self.shellQuote(project.path)) && PATH=/opt/homebrew/bin:/usr/local/bin:$PATH \(command) 2>&1 | tail -n 250"]
                )
                return ProjectLogSnapshot(text: output, updatedAt: Date(), sourceLabel: command)
            } catch {
                return ProjectLogSnapshot(text: error.localizedDescription, updatedAt: Date(), sourceLabel: command)
            }
        }
        let url = logURL(for: project)
        let text = (try? await CommandRunner.run("/usr/bin/tail", arguments: ["-n", "250", url.path])) ?? "Noch keine von Server Observer gestarteten Logs."
        return ProjectLogSnapshot(text: text, updatedAt: Date(), sourceLabel: "Server Observer Log")
    }

    private func logURL(for project: ProjectDescriptor) -> URL {
        let name = project.id.data(using: .utf8)?.base64EncodedString() ?? project.name
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        return logDirectory.appendingPathComponent(safeName + ".log")
    }

    private func forget(projectID: String, pid: Int32) {
        guard processes[projectID]?.processIdentifier == pid else { return }
        processes.removeValue(forKey: projectID)
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
