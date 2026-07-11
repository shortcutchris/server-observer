import Foundation

enum PortConflictDetector {
    static func detect(
        projects: [MonitoredProject],
        unassignedServers: [LocalServer] = [],
        unassignedContainers: [DockerContainer] = []
    ) -> [String: [PortConflict]] {
        var owners: [Int: [(label: String, path: String?, pid: Int32?)]] = [:]
        for project in projects {
            for server in project.servers {
                for port in server.ports {
                    owners[port, default: []].append((server.displayName, project.id, server.pid))
                }
            }
            for container in project.containers where container.isActive {
                for port in container.ports.compactMap(\.hostPort) {
                    owners[port, default: []].append((container.displayName, project.id, nil))
                }
            }
        }
        for server in unassignedServers {
            for port in server.ports { owners[port, default: []].append((server.displayName, nil, server.pid)) }
        }
        for container in unassignedContainers where container.isActive {
            for port in container.ports.compactMap(\.hostPort) {
                owners[port, default: []].append((container.displayName, nil, nil))
            }
        }

        var result: [String: [PortConflict]] = [:]
        for project in projects {
            for port in project.descriptor.recipe.allExpectedPorts {
                for owner in owners[port] ?? [] where owner.path != project.id {
                    result[project.id, default: []].append(
                        PortConflict(
                            port: port,
                            expectedByProject: project.descriptor.name,
                            occupiedBy: owner.label,
                            ownerProjectPath: owner.path,
                            pid: owner.pid
                        )
                    )
                }
            }
        }
        return result
    }
}
