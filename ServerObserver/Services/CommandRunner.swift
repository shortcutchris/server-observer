import Foundation

enum CommandRunner {
    static func run(_ executable: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors

            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 || !data.isEmpty else {
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: errorData, as: UTF8.self)
                throw CommandError.failed(executable: executable, message: message)
            }

            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

enum CommandError: LocalizedError {
    case failed(executable: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .failed(executable, message):
            "\(executable) konnte nicht ausgeführt werden. \(message)"
        }
    }
}

