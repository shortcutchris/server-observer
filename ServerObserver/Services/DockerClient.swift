import Foundation

actor DockerClient {
    private let executable: String?

    init(fileManager: FileManager = .default) {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".docker/bin/docker").path,
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        executable = candidates.first(where: fileManager.isExecutableFile(atPath:))
    }

    func scan(projects: [ProjectDescriptor]) async -> DockerSnapshot {
        guard let executable else {
            return DockerSnapshot(state: .unavailable, containers: [])
        }

        let version: String
        do {
            version = try await CommandRunner.run(executable, arguments: ["info", "--format", "{{.ServerVersion}}"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return DockerSnapshot(state: .stopped, containers: [])
        }

        do {
            let idOutput = try await CommandRunner.run(executable, arguments: ["ps", "-aq"])
            let ids = idOutput.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard !ids.isEmpty else {
                return DockerSnapshot(state: .ready(version: version), containers: [])
            }

            let inspectOutput = try await CommandRunner.run(executable, arguments: ["inspect"] + ids)
            let data = Data(inspectOutput.utf8)
            let parsed = try Self.parseInspectJSON(data, projects: projects)
            var enriched: [DockerContainer] = []

            for container in parsed {
                let httpPort = container.isRunning
                    ? await Self.firstHTTPPort(in: container.ports.compactMap(\.hostPort))
                    : nil
                let kind: DockerContainerKind = container.kind == .database
                    ? .database
                    : (httpPort == nil ? .worker : .web)
                enriched.append(
                    DockerContainer(
                        id: container.id,
                        name: container.name,
                        image: container.image,
                        state: container.state,
                        health: container.health,
                        ports: container.ports,
                        mounts: container.mounts,
                        composeProject: container.composeProject,
                        composeService: container.composeService,
                        projectPath: container.projectPath,
                        kind: kind,
                        httpPort: httpPort
                    )
                )
            }

            return DockerSnapshot(
                state: .ready(version: version),
                containers: enriched.sorted {
                    if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
            )
        } catch {
            return DockerSnapshot(state: .stopped, containers: [])
        }
    }

    func stop(containerID: String) async throws {
        guard let executable else { throw DockerClientError.cliUnavailable }
        _ = try await CommandRunner.run(executable, arguments: ["stop", "--time", "10", containerID])
    }

    func start(containerID: String) async throws {
        guard let executable else { throw DockerClientError.cliUnavailable }
        _ = try await CommandRunner.run(executable, arguments: ["start", containerID])
    }

    func metrics(containerIDs: [String]) async -> [String: RuntimeMetrics] {
        guard let executable, !containerIDs.isEmpty else { return [:] }
        do {
            let output = try await CommandRunner.run(
                executable,
                arguments: ["stats", "--no-stream", "--format", "{{json .}}"] + containerIDs
            )
            return Self.parseStats(output, requestedIDs: containerIDs)
        } catch {
            return [:]
        }
    }

    nonisolated static func parseStats(_ output: String, requestedIDs: [String]) -> [String: RuntimeMetrics] {
        var result: [String: RuntimeMetrics] = [:]
        for line in output.split(whereSeparator: \Character.isNewline) {
            guard
                let data = String(line).data(using: .utf8),
                let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let rawID = record["ID"] as? String ?? record["Container"] as? String ?? ""
            guard let id = requestedIDs.first(where: { $0.hasPrefix(rawID) || rawID.hasPrefix(String($0.prefix(12))) }) else {
                continue
            }
            let memory = parseByteCount((record["MemUsage"] as? String ?? "0").components(separatedBy: "/").first ?? "0")
            let networkParts = (record["NetIO"] as? String ?? "").components(separatedBy: "/")
            result[id] = RuntimeMetrics(
                cpuPercent: parsePercent(record["CPUPerc"] as? String),
                memoryBytes: memory,
                uptimeSeconds: nil,
                networkInputBytes: networkParts.first.map(parseByteCount),
                networkOutputBytes: networkParts.count > 1 ? parseByteCount(networkParts[1]) : nil,
                processCount: Int((record["PIDs"] as? String ?? "").trimmingCharacters(in: .whitespaces))
            )
        }
        return result
    }

    private nonisolated static func parsePercent(_ value: String?) -> Double {
        Double((value ?? "0").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private nonisolated static func parseByteCount(_ raw: String) -> UInt64 {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let number = Double(value.prefix { $0.isNumber || $0 == "." }) ?? 0
        let unit = value.lowercased().filter { $0.isLetter }
        let factor: Double = switch unit {
        case "b": 1
        case "kb": 1_000
        case "kib": 1_024
        case "mb": 1_000_000
        case "mib": 1_048_576
        case "gb": 1_000_000_000
        case "gib": 1_073_741_824
        case "tb": 1_000_000_000_000
        case "tib": 1_099_511_627_776
        default: 1
        }
        return UInt64(max(number * factor, 0))
    }

    nonisolated static func parseInspectJSON(
        _ data: Data,
        projects: [ProjectDescriptor]
    ) throws -> [DockerContainer] {
        guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DockerClientError.invalidResponse
        }

        return records.compactMap { record in
            guard let id = record["Id"] as? String else { return nil }
            let rawName = record["Name"] as? String ?? String(id.prefix(12))
            let name = rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName
            let config = record["Config"] as? [String: Any] ?? [:]
            let labels = config["Labels"] as? [String: String] ?? [:]
            let image = config["Image"] as? String ?? "Unbekanntes Image"
            let stateObject = record["State"] as? [String: Any] ?? [:]
            let state = stateObject["Status"] as? String ?? "unknown"
            let healthObject = stateObject["Health"] as? [String: Any]
            let health = DockerHealth(rawValue: healthObject?["Status"] as? String ?? "none") ?? .none
            let mounts = parseMounts(record["Mounts"])
            let ports = parsePorts(record["NetworkSettings"])
            let composeProject = nonEmpty(labels["com.docker.compose.project"])
            let composeService = nonEmpty(labels["com.docker.compose.service"])
            let projectPath = associateProject(
                labels: labels,
                mounts: mounts,
                composeProject: composeProject,
                projects: projects
            )
            let databaseText = "\(name) \(image) \(composeService ?? "")".lowercased()
            let kind: DockerContainerKind = isDatabase(databaseText) ? .database : .worker

            return DockerContainer(
                id: id,
                name: name,
                image: image,
                state: state,
                health: health,
                ports: ports,
                mounts: mounts,
                composeProject: composeProject,
                composeService: composeService,
                projectPath: projectPath,
                kind: kind,
                httpPort: nil
            )
        }
    }

    private nonisolated static func parseMounts(_ value: Any?) -> [DockerMount] {
        guard let values = value as? [[String: Any]] else { return [] }
        return values.compactMap { mount in
            guard
                let source = mount["Source"] as? String,
                let destination = mount["Destination"] as? String
            else { return nil }
            return DockerMount(
                source: source,
                destination: destination,
                type: mount["Type"] as? String ?? "unknown"
            )
        }
    }

    private nonisolated static func parsePorts(_ value: Any?) -> [DockerPort] {
        guard
            let network = value as? [String: Any],
            let values = network["Ports"] as? [String: Any]
        else { return [] }

        var result: [DockerPort] = []
        for (containerAddress, bindingsValue) in values {
            let parts = containerAddress.split(separator: "/", maxSplits: 1).map(String.init)
            guard let containerPort = Int(parts.first ?? "") else { continue }
            let protocolName = parts.count > 1 ? parts[1] : "tcp"

            if let bindings = bindingsValue as? [[String: Any]], !bindings.isEmpty {
                for binding in bindings {
                    result.append(
                        DockerPort(
                            containerPort: containerPort,
                            protocolName: protocolName,
                            hostIP: nonEmpty(binding["HostIp"] as? String),
                            hostPort: Int(binding["HostPort"] as? String ?? "")
                        )
                    )
                }
            } else {
                result.append(
                    DockerPort(
                        containerPort: containerPort,
                        protocolName: protocolName,
                        hostIP: nil,
                        hostPort: nil
                    )
                )
            }
        }
        let deduplicated = Dictionary(grouping: result) { port in
            "\(port.containerPort)/\(port.protocolName):\(port.hostPort.map(String.init) ?? "internal")"
        }
        .compactMap { $0.value.first }

        return deduplicated.sorted {
            ($0.hostPort ?? $0.containerPort) < ($1.hostPort ?? $1.containerPort)
        }
    }

    private nonisolated static func associateProject(
        labels: [String: String],
        mounts: [DockerMount],
        composeProject: String?,
        projects: [ProjectDescriptor]
    ) -> String? {
        var candidates: [String] = []
        let pathLabels = [
            "com.docker.compose.project.working_dir",
            "devcontainer.local_folder",
            "devcontainer.config_file",
            "com.docker.compose.project.config_files"
        ]

        for key in pathLabels {
            guard let value = nonEmpty(labels[key]) else { continue }
            for component in value.split(separator: ",") {
                candidates.append(projectDirectory(from: String(component)))
            }
        }
        candidates.append(contentsOf: mounts.filter { $0.type == "bind" }.map(\.source))

        for candidate in candidates {
            if let path = ProjectAssociation.projectPath(for: candidate, projects: projects) {
                return path
            }
        }

        if let composeProject {
            let normalizedComposeName = normalizedProjectName(composeProject)
            return projects.first {
                normalizedProjectName($0.name) == normalizedComposeName
                    || normalizedProjectName(URL(fileURLWithPath: $0.path).lastPathComponent) == normalizedComposeName
            }?.path
        }
        return nil
    }

    private nonisolated static func projectDirectory(from rawValue: String) -> String {
        let decoded = rawValue.removingPercentEncoding ?? rawValue
        let path: String
        if decoded.hasPrefix("file://"), let url = URL(string: decoded) {
            path = url.path
        } else {
            path = decoded
        }

        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent.lowercased()
        if filename == "devcontainer.json" {
            return url.deletingLastPathComponent().deletingLastPathComponent().path
        }
        if ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"].contains(filename) {
            return url.deletingLastPathComponent().path
        }
        return path
    }

    private nonisolated static func normalizedProjectName(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private nonisolated static func isDatabase(_ value: String) -> Bool {
        ["postgres", "mysql", "mariadb", "mongo", "redis", "valkey", "clickhouse", "elasticsearch"]
            .contains(where: value.contains)
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "<nil>" else { return nil }
        return value
    }

    private nonisolated static func firstHTTPPort(in ports: [Int]) async -> Int? {
        for port in Array(Set(ports)).sorted().prefix(5) {
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 0.6
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
}

enum DockerClientError: LocalizedError {
    case cliUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cliUnavailable: "Docker CLI wurde nicht gefunden."
        case .invalidResponse: "Die Docker-Antwort konnte nicht gelesen werden."
        }
    }
}
