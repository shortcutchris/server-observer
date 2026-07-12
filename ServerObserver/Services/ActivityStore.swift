import Foundation

actor ActivityStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ServerObserver", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("activity.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [ActivityEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([ActivityEvent].self, from: data)) ?? []
    }

    func append(_ event: ActivityEvent, to current: [ActivityEvent]) -> [ActivityEvent] {
        let updated = Array(([event] + current).prefix(500))
        persist(updated)
        return updated
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist(_ events: [ActivityEvent]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(events).write(to: fileURL, options: .atomic)
        } catch {
            // Der Verlauf ist ergänzend; Monitoring und Steuerung bleiben verfügbar.
        }
    }
}
