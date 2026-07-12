import Foundation

actor GitInspector {
    func inspect(projects: [ProjectDescriptor]) async -> [String: GitStatus] {
        await withTaskGroup(of: (String, GitStatus?).self) { group in
            for project in projects where project.markers.contains(.git) {
                group.addTask { (project.path, await Self.inspect(path: project.path)) }
            }
            var statuses: [String: GitStatus] = [:]
            for await (path, status) in group {
                if let status { statuses[path] = status }
            }
            return statuses
        }
    }

    private nonisolated static func inspect(path: String) async -> GitStatus? {
        do {
            async let statusOutput = CommandRunner.run(
                "/usr/bin/git", arguments: ["-C", path, "status", "--porcelain=v1", "--branch"]
            )
            async let latestCommit = try? CommandRunner.run(
                "/usr/bin/git", arguments: ["-C", path, "log", "-1", "--pretty=%h %s"]
            )
            async let remoteURL = try? CommandRunner.run(
                "/usr/bin/git", arguments: ["-C", path, "remote", "get-url", "origin"]
            )
            let output = try await statusOutput
            return parse(
                output,
                latestCommit: await latestCommit?.trimmingCharacters(in: .whitespacesAndNewlines),
                remoteURL: await remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            return nil
        }
    }

    nonisolated static func parse(_ output: String, latestCommit: String?, remoteURL: String?) -> GitStatus? {
        let lines = output.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let header = lines.first, header.hasPrefix("## ") else { return nil }
        let branchSection = String(header.dropFirst(3))
        let branch = branchSection
            .components(separatedBy: "...").first?
            .components(separatedBy: " [").first ?? branchSection
        let ahead = captureCount(in: branchSection, marker: "ahead ")
        let behind = captureCount(in: branchSection, marker: "behind ")
        return GitStatus(
            branch: branch,
            changedFileCount: max(lines.count - 1, 0),
            ahead: ahead,
            behind: behind,
            latestCommit: latestCommit?.nilIfEmpty,
            remoteURL: remoteURL?.nilIfEmpty
        )
    }

    private nonisolated static func captureCount(in value: String, marker: String) -> Int {
        guard let range = value.range(of: marker) else { return 0 }
        return Int(value[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
