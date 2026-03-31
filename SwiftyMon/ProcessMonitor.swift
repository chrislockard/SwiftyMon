import Foundation
import Combine

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published var appGroups: [AppGroup] = []
    @Published var statusMessage: String = "Starting…"
    @Published var refreshInterval: TimeInterval = 3.0

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        triggerRefresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() {
        triggerRefresh()
    }

    func setInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        timer?.invalidate()
        if timer != nil { scheduleTimer() }
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerRefresh() }
        }
    }

    private func triggerRefresh() {
        Task.detached(priority: .userInitiated) {
            let output = ProcessMonitor.runPS()
            let groups = ProcessMonitor.parseAndGroup(output)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.appGroups = groups
                self.statusMessage = "\(groups.count) apps"
            }
        }
    }

    // MARK: - Static helpers (no actor isolation, run freely on any thread)

    private nonisolated static func runPS() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,pcpu,rss,comm"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }

    private nonisolated static func parseAndGroup(_ output: String) -> [AppGroup] {
        var grouped: [String: [ProcessInfo]] = [:]
        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", maxSplits: 3,
                                  omittingEmptySubsequences: true)
            guard cols.count >= 4,
                  let pid = Int(cols[0]),
                  let cpu = Double(cols[1]),
                  let rss = Double(cols[2]) else { continue }
            let commPath = cols[3].trimmingCharacters(in: .whitespaces)
            let name = String(commPath.split(separator: "/").last ?? Substring(commPath))
            grouped[name, default: []].append(
                ProcessInfo(pid: pid, name: name, cpu: cpu, memMB: rss / 1_024)
            )
        }
        return grouped
            .map { AppGroup(name: $0.key, processes: $0.value) }
            .sorted { $0.totalCPU > $1.totalCPU }
    }
}
