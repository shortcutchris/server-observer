import Foundation

actor ProjectScanner {
    private static let excludedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", ".idea", ".vscode", "DerivedData",
        "Pods", "build", "dist", "node_modules", "target", "vendor", "venv", ".venv"
    ]

    func scan(roots: [ProjectRoot]) async -> [ProjectDescriptor] {
        await Task.detached(priority: .utility) {
            var candidates: [ProjectDescriptor] = []
            for root in roots where root.isEnabled {
                candidates.append(contentsOf: Self.scan(root: root))
            }
            return Self.removeManifestOnlyNestedProjects(from: candidates)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    nonisolated static func scan(root: ProjectRoot) -> [ProjectDescriptor] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: root.path).standardizedFileURL
        let rootComponentCount = PathUtilities.normalized(rootURL.path).split(separator: "/").count
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        var projects: [ProjectDescriptor] = []
        inspectDirectory(rootURL, depth: 0, root: root, into: &projects)

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return projects }

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey]), values.isDirectory == true else {
                continue
            }

            let name = url.lastPathComponent
            let canonicalComponentCount = PathUtilities.normalized(url.path).split(separator: "/").count
            let depth = max(0, canonicalComponentCount - rootComponentCount)
            if excludedDirectories.contains(name) || values.isHidden == true || depth >= root.scanDepth {
                enumerator.skipDescendants()
            }
            guard !excludedDirectories.contains(name), values.isHidden != true, depth <= root.scanDepth else { continue }
            inspectDirectory(url, depth: depth, root: root, into: &projects)
        }

        return projects
    }

    private nonisolated static func inspectDirectory(
        _ url: URL,
        depth: Int,
        root: ProjectRoot,
        into projects: inout [ProjectDescriptor]
    ) {
        let markers = markers(at: url)
        guard !markers.isEmpty else { return }
        let hasStrongMarker = markers.contains(where: \.isStrongProjectBoundary)
        guard hasStrongMarker || depth <= 2 else { return }
        let recipe = ProjectRecipeLoader.load(at: url, markers: markers)

        projects.append(
            ProjectDescriptor(
                path: PathUtilities.normalized(url.path),
                name: recipe.displayName ?? projectName(at: url),
                rootID: root.id,
                markers: markers,
                recipe: recipe
            )
        )
    }

    nonisolated static func markers(at url: URL) -> Set<ProjectMarker> {
        let fileManager = FileManager.default
        func exists(_ component: String) -> Bool {
            fileManager.fileExists(atPath: url.appendingPathComponent(component).path)
        }

        var markers: Set<ProjectMarker> = []
        if exists(".git") { markers.insert(.git) }
        if ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"].contains(where: exists) {
            markers.insert(.compose)
        }
        if exists(".devcontainer/devcontainer.json") { markers.insert(.devContainer) }
        if exists("Dockerfile") { markers.insert(.dockerfile) }
        if exists("package.json") { markers.insert(.node) }
        if exists("pyproject.toml") || exists("requirements.txt") { markers.insert(.python) }
        if exists("Package.swift") || exists("project.yml") { markers.insert(.swift) }
        if exists("go.mod") { markers.insert(.go) }
        if exists("Cargo.toml") { markers.insert(.rust) }
        if exists("pom.xml") || exists("build.gradle") || exists("build.gradle.kts") { markers.insert(.java) }
        return markers
    }

    private nonisolated static func projectName(at url: URL) -> String {
        let packageURL = url.appendingPathComponent("package.json")
        if
            let data = try? Data(contentsOf: packageURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = object["name"] as? String,
            !name.isEmpty
        {
            return name
        }
        return url.lastPathComponent
    }

    private nonisolated static func removeManifestOnlyNestedProjects(
        from candidates: [ProjectDescriptor]
    ) -> [ProjectDescriptor] {
        let unique = Dictionary(grouping: candidates, by: \.path).compactMap { _, entries -> ProjectDescriptor? in
            guard let first = entries.first else { return nil }
            return ProjectDescriptor(
                path: first.path,
                name: first.name,
                rootID: first.rootID,
                markers: entries.reduce(into: Set<ProjectMarker>()) { $0.formUnion($1.markers) },
                recipe: first.recipe
            )
        }

        return unique.filter { candidate in
            if candidate.markers.contains(where: \.isStrongProjectBoundary) { return true }
            return !unique.contains { parent in
                parent.path != candidate.path
                    && parent.markers.contains(where: \.isStrongProjectBoundary)
                    && PathUtilities.isPath(candidate.path, inside: parent.path)
            }
        }
    }
}
