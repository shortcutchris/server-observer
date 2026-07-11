import Foundation

actor ServerScanner {
    private let currentUID = getuid()

    func scan() async throws -> [LocalServer] {
        let raw = try await CommandRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-FpcuLnT", "-iTCP", "-sTCP:LISTEN"]
        )

        let endpoints = Self.parseLsof(raw)
            .filter { $0.ownerUID == currentUID && $0.pid != getpid() }

        guard !endpoints.isEmpty else { return [] }

        let grouped = Dictionary(grouping: endpoints, by: \ListeningEndpoint.pid)
        let metadata = await loadMetadata(for: Array(grouped.keys))

        return await withTaskGroup(of: LocalServer?.self, returning: [LocalServer].self) { group in
            for (pid, processEndpoints) in grouped {
                group.addTask {
                    guard let first = processEndpoints.first else { return nil }
                    let info = metadata[pid] ?? ProcessMetadata(command: first.processName, workingDirectory: nil)
                    let ports = Array(Set(processEndpoints.map(\.port))).sorted()
                    let hosts = Array(Set(processEndpoints.map(\.host))).sorted()
                    let httpPort = await Self.firstHTTPPort(in: ports)
                    return Self.makeServer(
                        endpoint: first,
                        ports: ports,
                        hosts: hosts,
                        metadata: info,
                        httpPort: httpPort
                    )
                }
            }

            var result: [LocalServer] = []
            for await server in group {
                if let server { result.append(server) }
            }
            return result.sorted {
                if ($0.kind == .web) != ($1.kind == .web) { return $0.kind == .web }
                return $0.primaryPort < $1.primaryPort
            }
        }
    }

    nonisolated static func parseLsof(_ output: String) -> [ListeningEndpoint] {
        var pid: Int32?
        var processName = "Unbekannt"
        var ownerUID: UInt32?
        var endpoints: [ListeningEndpoint] = []

        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                pid = Int32(value)
                processName = "Unbekannt"
                ownerUID = nil
            case "c":
                processName = value
            case "u":
                ownerUID = UInt32(value)
            case "n":
                guard
                    let pid,
                    let ownerUID,
                    let endpoint = parseEndpoint(value)
                else { continue }
                endpoints.append(
                    ListeningEndpoint(
                        pid: pid,
                        processName: processName,
                        ownerUID: ownerUID,
                        host: endpoint.host,
                        port: endpoint.port
                    )
                )
            default:
                continue
            }
        }

        return Array(Set(endpoints))
    }

    private nonisolated static func parseEndpoint(_ value: String) -> (host: String, port: Int)? {
        let endpoint = value.components(separatedBy: "->").first ?? value
        guard let separator = endpoint.lastIndex(of: ":") else { return nil }
        let host = String(endpoint[..<separator])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard let port = Int(endpoint[endpoint.index(after: separator)...]) else { return nil }
        return (host.isEmpty ? "*" : host, port)
    }

    private func loadMetadata(for pids: [Int32]) async -> [Int32: ProcessMetadata] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")

        async let commandsOutput = try? CommandRunner.run(
            "/bin/ps",
            arguments: ["-p", pidList, "-o", "pid=", "-o", "command="]
        )
        async let cwdOutput = try? CommandRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-a", "-p", pidList, "-d", "cwd", "-Fn"]
        )

        let commands = Self.parseCommands(await commandsOutput ?? "")
        let directories = Self.parseWorkingDirectories(await cwdOutput ?? "")

        return Dictionary(uniqueKeysWithValues: pids.map { pid in
            (
                pid,
                ProcessMetadata(
                    command: commands[pid] ?? "",
                    workingDirectory: directories[pid]
                )
            )
        })
    }

    private nonisolated static func parseCommands(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for line in output.split(whereSeparator: \Character.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            result[pid] = String(parts[1])
        }
        return result
    }

    private nonisolated static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            if prefix == "p" { currentPID = Int32(value) }
            if prefix == "n", let currentPID { result[currentPID] = value }
        }
        return result
    }

    private nonisolated static func firstHTTPPort(in ports: [Int]) async -> Int? {
        for port in ports.prefix(4) {
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 0.65
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if response is HTTPURLResponse { return port }
            } catch {
                continue
            }
        }
        return nil
    }

    private nonisolated static func makeServer(
        endpoint: ListeningEndpoint,
        ports: [Int],
        hosts: [String],
        metadata: ProcessMetadata,
        httpPort: Int?
    ) -> LocalServer {
        let fullText = "\(endpoint.processName) \(metadata.command)".lowercased()
        let runtime = detectRuntime(in: fullText)
        let service = detectService(in: fullText)
        let packagedApplication = packagedApplicationName(in: metadata.command)
        let isDesktopService = packagedApplication != nil || metadata.command.hasPrefix("/System/")
        let kind: LocalServer.Kind
        if service.isDatabase {
            kind = .database
        } else if isDesktopService {
            kind = .service
        } else if httpPort != nil {
            kind = .web
        } else if runtime != "Prozess" {
            kind = .service
        } else {
            kind = .unknown
        }

        let projectName = projectName(at: metadata.workingDirectory)
        let displayName = service.name ?? packagedApplication ?? projectName ?? endpoint.processName
        let orderedPorts: [Int]
        if let httpPort {
            orderedPorts = [httpPort] + ports.filter { $0 != httpPort }
        } else {
            orderedPorts = ports
        }

        return LocalServer(
            pid: endpoint.pid,
            processName: endpoint.processName,
            displayName: displayName,
            runtime: service.runtimeLabel ?? (packagedApplication == nil ? runtime : "Desktop-Dienst"),
            command: metadata.command.isEmpty ? endpoint.processName : metadata.command,
            workingDirectory: metadata.workingDirectory,
            ports: orderedPorts,
            hosts: hosts,
            kind: kind,
            isHTTP: httpPort != nil,
            ownerUID: endpoint.ownerUID
        )
    }

    private nonisolated static func detectRuntime(in text: String) -> String {
        if text.contains("next") { return "Next.js" }
        if text.contains("vite") { return "Vite" }
        if text.contains("node") || text.contains("npm") || text.contains("bun") { return "Node.js" }
        if text.contains("uvicorn") || text.contains("fastapi") { return "FastAPI" }
        if text.contains("python") { return "Python" }
        if text.contains("ruby") || text.contains("rails") { return "Ruby" }
        if text.contains("java") { return "Java" }
        if text.contains("php") { return "PHP" }
        if text.contains("go-build") { return "Go" }
        return "Prozess"
    }

    private nonisolated static func detectService(in text: String) -> (name: String?, runtimeLabel: String?, isDatabase: Bool) {
        if text.contains("postgres") { return ("PostgreSQL", "PostgreSQL", true) }
        if text.contains("redis-server") { return ("Redis", "Redis", true) }
        if text.contains("mongod") { return ("MongoDB", "MongoDB", true) }
        if text.contains("mysqld") { return ("MySQL", "MySQL", true) }
        if text.contains("com.docker") || text.contains("docker desktop") { return ("Docker", "Docker", false) }
        return (nil, nil, false)
    }

    private nonisolated static func packagedApplicationName(in command: String) -> String? {
        guard let appRange = command.range(of: ".app/") else { return nil }
        let prefix = command[..<appRange.lowerBound]
        guard let slash = prefix.lastIndex(of: "/") else { return nil }
        let name = prefix[prefix.index(after: slash)...]
        return name.isEmpty ? nil : String(name)
    }

    private nonisolated static func projectName(at directory: String?) -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        let url = URL(fileURLWithPath: directory)

        for candidate in [url, url.deletingLastPathComponent()] {
            let packageURL = candidate.appendingPathComponent("package.json")
            if
                let data = try? Data(contentsOf: packageURL),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let name = object["name"] as? String,
                !name.isEmpty
            {
                return name
            }
        }

        let component = url.lastPathComponent
        return component.isEmpty ? nil : component
    }
}

private struct ProcessMetadata: Sendable {
    let command: String
    let workingDirectory: String?
}
