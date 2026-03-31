import Foundation
import Observation

@Observable
final class ProcessMonitor {
    var appGroups: [AppGroup] = []
    var lastUpdated: Date = .now
    var isRunning = false
    var refreshInterval: TimeInterval = 3.0
    var statusMessage: String = "Starting…"

    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?

    // Mutable only from the single serialized fetch task
    private var prevNetBytes: [String: (inBytes: Int64, outBytes: Int64)] = [:]
    private var prevSampleTime: Date = .distantPast

    func start() {
        guard !isRunning else { return }
        isRunning = true
        triggerRefresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fetchTask?.cancel()
        fetchTask = nil
        isRunning = false
    }

    func refreshNow() {
        fetchTask?.cancel()
        triggerRefresh()
    }

    func setInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if isRunning {
            timer?.invalidate()
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.triggerRefresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func triggerRefresh() {
        fetchTask?.cancel()
        fetchTask = Task {
            guard !Task.isCancelled else { return }
            do {
                let groups = try await fetchGroups()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.appGroups = groups
                    self.lastUpdated = .now
                    self.statusMessage = "Updated \(groups.count) apps"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func fetchGroups() async throws -> [AppGroup] {
        // Run ps and nettop sequentially (nettop takes ~1s to sample)
        let psOutput  = try await runCommand("/bin/ps",          args: ["-eo", "pid,pcpu,rss,comm"])
        let netOutput = try await runCommand("/usr/bin/nettop",  args: ["-l", "1", "-P"])

        let processes = parsePS(psOutput)
        let netSample = parseNettop(netOutput)

        let now = Date.now
        let elapsed = prevSampleTime == .distantPast
            ? refreshInterval
            : max(now.timeIntervalSince(prevSampleTime), 0.5)

        var rates: [String: (inBPS: Double, outBPS: Double)] = [:]
        if prevSampleTime != .distantPast {
            for (key, curr) in netSample {
                if let prev = prevNetBytes[key] {
                    rates[key] = (
                        inBPS:  Double(max(0, curr.inBytes  - prev.inBytes))  / elapsed,
                        outBPS: Double(max(0, curr.outBytes - prev.outBytes)) / elapsed
                    )
                }
            }
        }
        prevNetBytes = netSample
        prevSampleTime = now

        // Group processes by app name
        var grouped: [String: [ProcessInfo]] = [:]
        for var proc in processes {
            let netKey = "\(proc.name).\(proc.pid)"
            if let rate = rates[netKey] {
                proc.netInBPS  = rate.inBPS
                proc.netOutBPS = rate.outBPS
            }
            grouped[proc.name, default: []].append(proc)
        }

        return grouped
            .map { AppGroup(name: $0.key, processes: $0.value) }
            .sorted { $0.totalCPU > $1.totalCPU }
    }

    // MARK: - Parsers

    private func parsePS(_ output: String) -> [ProcessInfo] {
        output.components(separatedBy: "\n")
            .dropFirst()
            .compactMap { line -> ProcessInfo? in
                let cols = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard cols.count >= 4,
                      let pid = Int(cols[0]),
                      let cpu = Double(cols[1]),
                      let rss = Double(cols[2]) else { return nil }

                let commPath = cols[3].trimmingCharacters(in: .whitespaces)
                let name = String(commPath.split(separator: "/").last ?? Substring(commPath))
                return ProcessInfo(pid: pid, name: name, cpu: cpu,
                                   memMB: rss / 1_024, netInBPS: 0, netOutBPS: 0)
            }
    }

    private func parseNettop(_ output: String) -> [String: (inBytes: Int64, outBytes: Int64)] {
        var result: [String: (inBytes: Int64, outBytes: Int64)] = [:]

        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 2 else { continue }

            let procField = String(cols[1])
            // procField is "name.pid" — split on last dot
            guard let lastDot = procField.lastIndex(of: "."),
                  Int(procField[procField.index(after: lastDot)...]) != nil else { continue }

            // Collect all "number unit" pairs in this line
            var byteValues: [Int64] = []
            var i = cols.startIndex
            while i < cols.endIndex {
                let ci = cols.index(after: i)
                guard ci < cols.endIndex else { break }
                if let val = Double(cols[i]) {
                    let unit = String(cols[ci])
                    let bytes: Int64?
                    switch unit {
                    case "B":   bytes = Int64(val)
                    case "KiB": bytes = Int64(val * 1_024)
                    case "MiB": bytes = Int64(val * 1_048_576)
                    case "GiB": bytes = Int64(val * 1_073_741_824)
                    default:    bytes = nil
                    }
                    if let b = bytes {
                        byteValues.append(b)
                        i = cols.index(ci, offsetBy: 1, limitedBy: cols.endIndex) ?? cols.endIndex
                        if byteValues.count == 2 { break }
                        continue
                    }
                }
                i = cols.index(after: i)
            }

            guard byteValues.count >= 2 else { continue }
            result[procField] = (inBytes: byteValues[0], outBytes: byteValues[1])
        }
        return result
    }

    // MARK: - Command runner

    private func runCommand(_ path: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
