import Foundation

enum ProjectRecipeLoader {
    static func load(at projectURL: URL, markers: Set<ProjectMarker>) -> ProjectRecipe {
        let automatic = automaticRecipe(at: projectURL, markers: markers)
        let yamlURL = projectURL.appendingPathComponent(".server-observer.yml")
        let yamlAlternative = projectURL.appendingPathComponent(".server-observer.yaml")
        let jsonURL = projectURL.appendingPathComponent(".server-observer.json")

        if let data = try? Data(contentsOf: jsonURL),
           let configured = try? JSONDecoder().decode(ProjectRecipe.self, from: data)
        {
            return merge(automatic: automatic, configured: configured)
        }

        let selectedYAML = FileManager.default.fileExists(atPath: yamlURL.path) ? yamlURL : yamlAlternative
        if let text = try? String(contentsOf: selectedYAML, encoding: .utf8) {
            return merge(automatic: automatic, configured: parseYAML(text))
        }
        return automatic
    }

    static func parseYAML(_ text: String) -> ProjectRecipe {
        enum Section { case root, profiles, services }
        var recipe = ProjectRecipe(source: .configuration)
        var section = Section.root
        var currentProfile: ProjectProfile?
        var currentService: ProjectService?

        func cleanedValue(_ raw: String) -> String {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value.removeFirst()
                value.removeLast()
            }
            return value
        }

        func split(_ line: String) -> (String, String)? {
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = cleanedValue(String(line[line.index(after: separator)...]))
            return (key, value)
        }

        func removingComment(from line: String) -> String {
            var quote: Character?
            for index in line.indices {
                let character = line[index]
                if character == "\"" || character == "'" {
                    quote = quote == character ? nil : (quote == nil ? character : quote)
                } else if character == "#", quote == nil,
                          (index == line.startIndex || line[line.index(before: index)].isWhitespace) {
                    return String(line[..<index])
                }
            }
            return line
        }

        func flushProfile() {
            if let currentProfile, !currentProfile.startCommand.isEmpty {
                recipe.profiles.append(currentProfile)
            }
            currentProfile = nil
        }

        func flushService() {
            if let currentService, !currentService.url.isEmpty {
                recipe.services.append(currentService)
            }
            currentService = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let withoutComment = removingComment(from: rawLine)
            guard !withoutComment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let indentation = withoutComment.prefix { $0 == " " }.count
            let line = withoutComment.trimmingCharacters(in: .whitespaces)

            if indentation == 0 {
                flushProfile()
                flushService()
                section = .root
                if line == "profiles:" { section = .profiles; continue }
                if line == "services:" { section = .services; continue }
                guard let (key, value) = split(line) else { continue }
                switch key.lowercased() {
                case "name": recipe.displayName = value
                case "start": recipe.startCommand = nonEmpty(value)
                case "stop": recipe.stopCommand = nonEmpty(value)
                case "restart": recipe.restartCommand = nonEmpty(value)
                case "logs", "log": recipe.logCommand = nonEmpty(value)
                case "health": recipe.healthURL = nonEmpty(value)
                case "ports": recipe.expectedPorts = parsePorts(value)
                case "notifications": recipe.notificationsEnabled = parseBoolean(value)
                default: continue
                }
                continue
            }

            switch section {
            case .profiles:
                if indentation <= 2, line.hasSuffix(":"), !line.contains(": ") {
                    flushProfile()
                    currentProfile = ProjectProfile(
                        name: String(line.dropLast()).trimmingCharacters(in: .whitespaces),
                        startCommand: "",
                        stopCommand: nil
                    )
                } else if let (key, value) = split(line), currentProfile != nil {
                    switch key.lowercased() {
                    case "start": currentProfile?.startCommand = value
                    case "stop": currentProfile?.stopCommand = nonEmpty(value)
                    default: continue
                    }
                }
            case .services:
                if indentation <= 2, line.hasSuffix(":"), !line.contains(": ") {
                    flushService()
                    currentService = ProjectService(
                        name: String(line.dropLast()).trimmingCharacters(in: .whitespaces),
                        url: "",
                        healthURL: nil,
                        isFrontend: nil
                    )
                } else if let (key, value) = split(line), currentService != nil {
                    switch key.lowercased() {
                    case "url": currentService?.url = value
                    case "health": currentService?.healthURL = nonEmpty(value)
                    case "frontend", "primary": currentService?.isFrontend = parseBoolean(value)
                    default: continue
                    }
                }
            case .root:
                continue
            }
        }
        flushProfile()
        flushService()
        recipe.expectedPorts = Array(Set(recipe.expectedPorts)).sorted()
        return recipe
    }

    private static func automaticRecipe(at projectURL: URL, markers: Set<ProjectMarker>) -> ProjectRecipe {
        if markers.contains(.compose) {
            return ProjectRecipe(
                startCommand: "docker compose up -d",
                stopCommand: "docker compose stop",
                restartCommand: "docker compose restart",
                logCommand: "docker compose logs --tail 150",
                profiles: [
                    ProjectProfile(
                        name: "Full Stack",
                        startCommand: "docker compose up -d",
                        stopCommand: "docker compose stop"
                    )
                ]
            )
        }

        if markers.contains(.node),
           let data = try? Data(contentsOf: projectURL.appendingPathComponent("package.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = object["scripts"] as? [String: Any]
        {
            let script = scripts["dev"] != nil ? "dev" : (scripts["start"] != nil ? "start" : nil)
            if let script {
                let runner: String
                if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("pnpm-lock.yaml").path) {
                    runner = "pnpm"
                } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("bun.lock").path)
                            || FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("bun.lockb").path) {
                    runner = "bun run"
                } else if FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("yarn.lock").path) {
                    runner = "yarn"
                } else {
                    runner = "npm run"
                }
                return ProjectRecipe(startCommand: "\(runner) \(script)")
            }
        }

        if markers.contains(.swift) { return ProjectRecipe(startCommand: "swift run") }
        if markers.contains(.go) { return ProjectRecipe(startCommand: "go run .") }
        if markers.contains(.rust) { return ProjectRecipe(startCommand: "cargo run") }
        return ProjectRecipe()
    }

    private static func merge(automatic: ProjectRecipe, configured: ProjectRecipe) -> ProjectRecipe {
        ProjectRecipe(
            displayName: configured.displayName,
            startCommand: configured.startCommand ?? automatic.startCommand,
            stopCommand: configured.stopCommand ?? automatic.stopCommand,
            restartCommand: configured.restartCommand ?? automatic.restartCommand,
            logCommand: configured.logCommand ?? automatic.logCommand,
            healthURL: configured.healthURL ?? automatic.healthURL,
            expectedPorts: configured.expectedPorts.isEmpty ? automatic.expectedPorts : configured.expectedPorts,
            profiles: configured.profiles.isEmpty ? automatic.profiles : configured.profiles,
            services: configured.services.isEmpty ? automatic.services : configured.services,
            notificationsEnabled: configured.notificationsEnabled,
            source: .configuration
        )
    }

    private static func parsePorts(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "on", "1": true
        case "false", "no", "off", "0": false
        default: nil
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
