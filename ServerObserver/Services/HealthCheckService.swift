import Foundation

actor HealthCheckService {
    func check(projects: [MonitoredProject]) async -> [String: [ServiceHealth]] {
        await withTaskGroup(of: (String, [ServiceHealth]).self) { group in
            for project in projects {
                group.addTask {
                    let targets = Self.targets(for: project)
                    var values: [ServiceHealth] = []
                    for target in targets {
                        values.append(await Self.probe(name: target.name, url: target.url))
                    }
                    return (project.id, values)
                }
            }
            var result: [String: [ServiceHealth]] = [:]
            for await (path, values) in group { result[path] = values }
            return result
        }
    }

    private nonisolated static func targets(for project: MonitoredProject) -> [(name: String, url: URL)] {
        var values: [(name: String, url: URL)] = project.descriptor.recipe.services.compactMap { service in
            service.probeURL.map { (name: service.name, url: $0) }
        }
        if let rawURL = project.descriptor.recipe.healthURL, let url = URL(string: rawURL) {
            values.append((name: "Healthcheck", url: url))
        }
        if values.isEmpty {
            values.append(contentsOf: project.servers.compactMap { server in
                server.browserURL.map { (name: server.displayName, url: $0) }
            })
            values.append(contentsOf: project.containers.compactMap { container in
                container.browserURL.map { (name: container.displayName, url: $0) }
            })
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.url.absoluteString).inserted }
    }

    private nonisolated static func probe(name: String, url: URL) async -> ServiceHealth {
        let started = ContinuousClock.now
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            var (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 405 || http.statusCode == 501 {
                request.httpMethod = "GET"
                (_, response) = try await URLSession.shared.data(for: request)
            }
            let duration = started.duration(to: .now).components
            let milliseconds = Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
            guard let http = response as? HTTPURLResponse else {
                return value(name, url, .degraded, nil, milliseconds)
            }
            let state: ServiceHealthState = (200..<400).contains(http.statusCode) ? .healthy : .degraded
            return value(name, url, state, http.statusCode, milliseconds)
        } catch {
            return value(name, url, .unreachable, nil, nil)
        }
    }

    private nonisolated static func value(
        _ name: String,
        _ url: URL,
        _ state: ServiceHealthState,
        _ status: Int?,
        _ latency: Int?
    ) -> ServiceHealth {
        ServiceHealth(
            name: name,
            url: url.absoluteString,
            state: state,
            statusCode: status,
            latencyMilliseconds: latency,
            checkedAt: Date()
        )
    }
}
