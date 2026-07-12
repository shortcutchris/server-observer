import Foundation

actor RuntimeMetricsScanner {
    func scan(processIDs: [Int32]) async -> [Int32: RuntimeMetrics] {
        let ids = Array(Set(processIDs)).sorted()
        guard !ids.isEmpty else { return [:] }

        do {
            async let processOutput = CommandRunner.run(
                "/bin/ps",
                arguments: ["-p", ids.map(String.init).joined(separator: ","), "-o", "pid=,%cpu=,rss=,etime="]
            )
            async let networkOutput = try? CommandRunner.run(
                "/usr/bin/nettop",
                arguments: ["-P", "-x", "-L", "1", "-n", "-J", "bytes_in,bytes_out"]
                    + ids.flatMap { ["-p", String($0)] }
            )
            var metrics = Self.parsePS(try await processOutput)
            let network = Self.parseNettop(await networkOutput ?? "")
            for (pid, value) in network where metrics[pid] != nil {
                metrics[pid]?.networkInputBytes = value.input
                metrics[pid]?.networkOutputBytes = value.output
            }
            return metrics
        } catch {
            return [:]
        }
    }

    nonisolated static func parseNettop(_ output: String) -> [Int32: (input: UInt64, output: UInt64)] {
        var result: [Int32: (input: UInt64, output: UInt64)] = [:]
        for line in output.split(whereSeparator: \Character.isNewline).dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }
            let processAndPID = fields[1].split(separator: ".")
            guard let rawPID = processAndPID.last, let pid = Int32(rawPID) else { continue }
            result[pid] = (UInt64(fields[2]) ?? 0, UInt64(fields[3]) ?? 0)
        }
        return result
    }

    nonisolated static func parsePS(_ output: String) -> [Int32: RuntimeMetrics] {
        var result: [Int32: RuntimeMetrics] = [:]
        for line in output.split(whereSeparator: \Character.isNewline) {
            let fields = line.split(whereSeparator: \Character.isWhitespace)
            guard
                fields.count >= 4,
                let pid = Int32(fields[0]),
                let cpu = Double(fields[1]),
                let rssKilobytes = UInt64(fields[2])
            else { continue }

            result[pid] = RuntimeMetrics(
                cpuPercent: cpu,
                memoryBytes: rssKilobytes * 1_024,
                uptimeSeconds: parseElapsed(String(fields[3])),
                networkInputBytes: nil,
                networkOutputBytes: nil,
                processCount: 1
            )
        }
        return result
    }

    nonisolated static func parseElapsed(_ value: String) -> TimeInterval? {
        let dayParts = value.split(separator: "-", maxSplits: 1).map(String.init)
        let days: Int
        let clock: String
        if dayParts.count == 2 {
            days = Int(dayParts[0]) ?? 0
            clock = dayParts[1]
        } else {
            days = 0
            clock = value
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let hours = parts.count == 3 ? parts[0] : 0
        let minutes = parts.count == 3 ? parts[1] : parts[0]
        let seconds = parts.last ?? 0
        return TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }
}
