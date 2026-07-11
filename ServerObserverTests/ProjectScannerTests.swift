import Foundation
import XCTest
@testable import ServerObserver

final class ProjectScannerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServerObserverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testFindsStrongProjectMarkersAndIgnoresDependencies() throws {
        let app = temporaryDirectory.appendingPathComponent("AcmeApp", isDirectory: true)
        let dependency = app.appendingPathComponent("node_modules/hidden-package", isDirectory: true)
        let compose = temporaryDirectory.appendingPathComponent("Backend", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dependency, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compose, withIntermediateDirectories: true)
        try Data(#"{"name":"acme-app"}"#.utf8).write(to: app.appendingPathComponent("package.json"))
        try Data(#"{"name":"hidden"}"#.utf8).write(to: dependency.appendingPathComponent("package.json"))
        try Data("services: {}".utf8).write(to: compose.appendingPathComponent("compose.yaml"))

        let root = ProjectRoot(path: temporaryDirectory.path, scanDepth: 5)
        let projects = ProjectScanner.scan(root: root)

        XCTAssertEqual(Set(projects.map(\.name)), ["acme-app", "Backend"])
        XCTAssertTrue(projects.first(where: { $0.name == "acme-app" })?.markers.contains(.git) == true)
        XCTAssertTrue(projects.first(where: { $0.name == "Backend" })?.markers.contains(.compose) == true)
    }

    func testDoesNotPromoteNestedPackageManifestInsideGitProject() async throws {
        let repository = temporaryDirectory.appendingPathComponent("Monorepo", isDirectory: true)
        let package = repository.appendingPathComponent("packages/web", isDirectory: true)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"{"name":"web"}"#.utf8).write(to: package.appendingPathComponent("package.json"))

        let scanner = ProjectScanner()
        let projects = await scanner.scan(roots: [ProjectRoot(path: temporaryDirectory.path, scanDepth: 5)])

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.path, PathUtilities.normalized(repository.path))
    }

    func testRespectsMaximumDepth() throws {
        let deepProject = temporaryDirectory.appendingPathComponent("one/two/three", isDirectory: true)
        try FileManager.default.createDirectory(at: deepProject.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let shallow = ProjectScanner.scan(root: ProjectRoot(path: temporaryDirectory.path, scanDepth: 2))
        let deep = ProjectScanner.scan(root: ProjectRoot(path: temporaryDirectory.path, scanDepth: 3))

        XCTAssertTrue(shallow.isEmpty)
        XCTAssertEqual(deep.map(\.path), [PathUtilities.normalized(deepProject.path)])
    }
}
