import Foundation
import XCTest
@testable import ServerObserver

final class DockerClientTests: XCTestCase {
    func testParsesComposeContainerAndAssociatesWorkingDirectory() throws {
        let project = descriptor(path: "/Users/test/Projects/knowledge-recorder", name: "Knowledge Recorder")
        let json = #"""
        [{
          "Id": "abc123",
          "Name": "/knowledge-recorder-web-1",
          "Config": {
            "Image": "ghcr.io/acme/web:latest",
            "Labels": {
              "com.docker.compose.project": "knowledge-recorder",
              "com.docker.compose.service": "web",
              "com.docker.compose.project.working_dir": "/Users/test/Projects/knowledge-recorder"
            }
          },
          "State": {"Status": "running", "Health": {"Status": "healthy"}},
          "Mounts": [],
          "NetworkSettings": {"Ports": {
            "3000/tcp": [
              {"HostIp": "0.0.0.0", "HostPort": "4310"},
              {"HostIp": "::", "HostPort": "4310"}
            ],
            "9229/tcp": null
          }}
        }]
        """#

        let containers = try DockerClient.parseInspectJSON(Data(json.utf8), projects: [project])

        let container = try XCTUnwrap(containers.first)
        XCTAssertEqual(container.id, "abc123")
        XCTAssertEqual(container.displayName, "web")
        XCTAssertEqual(container.health, .healthy)
        XCTAssertEqual(container.projectPath, project.path)
        XCTAssertEqual(container.ports.first(where: { $0.containerPort == 3000 })?.hostPort, 4310)
        XCTAssertEqual(container.ports.filter { $0.containerPort == 3000 }.count, 1)
        XCTAssertNil(container.ports.first(where: { $0.containerPort == 9229 })?.hostPort)
    }

    func testUsesBindMountAndRecognizesDatabaseWithoutPublishedPort() throws {
        let project = descriptor(path: "/Users/test/Projects/tendergraph", name: "tendergraph")
        let json = #"""
        [{
          "Id": "db456",
          "Name": "/tendergraph-postgres",
          "Config": {"Image": "postgres:17", "Labels": {}},
          "State": {"Status": "running"},
          "Mounts": [{
            "Type": "bind",
            "Source": "/Users/test/Projects/tendergraph/database",
            "Destination": "/docker-entrypoint-initdb.d"
          }],
          "NetworkSettings": {"Ports": {"5432/tcp": null}}
        }]
        """#

        let containers = try DockerClient.parseInspectJSON(Data(json.utf8), projects: [project])

        let container = try XCTUnwrap(containers.first)
        XCTAssertEqual(container.projectPath, project.path)
        XCTAssertEqual(container.kind, .database)
        XCTAssertEqual(container.portsLabel, "intern:5432/tcp")
        XCTAssertNil(container.browserURL)
    }

    func testDevContainerConfigLabelMapsToRepository() throws {
        let project = descriptor(path: "/Users/test/Projects/swift-api", name: "swift-api")
        let json = #"""
        [{
          "Id": "dev789",
          "Name": "/swift-api-devcontainer",
          "Config": {
            "Image": "swift:6",
            "Labels": {"devcontainer.config_file": "file:///Users/test/Projects/swift-api/.devcontainer/devcontainer.json"}
          },
          "State": {"Status": "exited"},
          "Mounts": [],
          "NetworkSettings": {"Ports": {}}
        }]
        """#

        let container = try XCTUnwrap(
            DockerClient.parseInspectJSON(Data(json.utf8), projects: [project]).first
        )

        XCTAssertEqual(container.projectPath, project.path)
        XCTAssertFalse(container.isActive)
    }

    func testProjectAssociationUsesMostSpecificNestedProject() {
        let parent = descriptor(path: "/Users/test/Projects", name: "Projects")
        let child = descriptor(path: "/Users/test/Projects/client/app", name: "app")

        XCTAssertEqual(
            ProjectAssociation.projectPath(
                for: "/Users/test/Projects/client/app/Sources",
                projects: [parent, child]
            ),
            child.path
        )
    }

    private func descriptor(path: String, name: String) -> ProjectDescriptor {
        ProjectDescriptor(path: path, name: name, rootID: UUID(), markers: [.git])
    }
}
