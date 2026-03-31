import Foundation
import Observation

@MainActor
@Observable
final class ProcessMonitor {
    var appGroups: [AppGroup] = []
    var lastUpdated: Date = .now
    var isRunning = false
    var refreshInterval: TimeInterval = 3.0
    var statusMessage: String = "Starting…"

    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?

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
            // Safe: timer is added to RunLoop.main so always fires on the main thread.
            MainActor.assumeIsolated { self?.triggerRefresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func triggerRefresh() {
        fetchTask?.cancel()
        // Task inherits @MainActor isolation from the enclosing context.
        fetchTask = Task {
            guard !Task.isCancelled else { return }
            do {
                let groups = try await fetchGroups()
                guard !Task.isCancelled else { return }
                appGroups = groups
                lastUpdated = .now
                statusMessage = "\(groups.count) apps"
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    // Suspends at the first `await`, freeing the main actor while ps runs.
    private func fetchGroups() async throws -> [AppGroup] {
        let processes = try await runPS()
        var grouped: [String: [ProcessInfo]] = [:]
        for proc in processes {
            grouped[proc.name, default: []].append(proc)
        }
        return grouped
            .map { AppGroup(name: $0.key, processes: $0.value) }
            .sorted { $0.totalCPU > $1.totalCPU }
    }

    // nonisolated: touches no actor state, safe to call from any context.
    private nonisolated func runPS() async throws -> [ProcessInfo] {
        let output = try await runCommand("/bin/ps", args: ["-eo", "pid,pcpu,rss,comm"])
        return output.components(separatedBy: "\n")
            .dropFirst()
            .compactMap { line -> ProcessInfo? in
                let cols = line.split(separator: " ", maxSplits: 3,
                                      omittingEmptySubsequences: true)
                guard cols.count >= 4,
                      let pid = Int(cols[0]),
                      let cpu = Double(cols[1]),
                      let rss = Double(cols[2]) else { return nil }
                let commPath = cols[3].trimmingCharacters(in: .whitespaces)
                let name = String(commPath.split(separator: "/").last ?? Substring(commPath))
                return ProcessInfo(pid: pid, name: name, cpu: cpu, memMB: rss / 1_024)
            }
    }

    private nonisolated func runCommand(_ path: String, args: [String]) async throws -> String {
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
