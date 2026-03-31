import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @State private var sortOrder = [KeyPathComparator(\AppGroup.totalCPU, order: .reverse)]
    @State private var selectedApp: String? = nil
    @State private var searchText = ""

    private var displayGroups: [AppGroup] {
        let base = searchText.isEmpty
            ? monitor.appGroups
            : monitor.appGroups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return base.sorted(using: sortOrder)
    }

    private var selectedGroup: AppGroup? {
        guard let sel = selectedApp else { return nil }
        return monitor.appGroups.first { $0.id == sel }
    }

    var body: some View {
        VStack(spacing: 0) {
            appTable
            if let group = selectedGroup {
                Divider()
                ProcessDetailView(group: group)
                    .frame(height: 200)
            }
        }
        .toolbar { toolbarContent }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter apps…")
        .navigationTitle("SwiftyMon")
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - Main Table

    private var appTable: some View {
        Table(displayGroups, selection: $selectedApp, sortOrder: $sortOrder) {
            TableColumn("Application", value: \.name) { group in
                HStack(spacing: 6) {
                    Circle()
                        .fill(cpuColor(group.totalCPU))
                        .frame(width: 8, height: 8)
                    Text(group.name)
                        .lineLimit(1)
                    if group.pidCount > 1 {
                        Text("×\(group.pidCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 160, ideal: 260)

            TableColumn("CPU", value: \.totalCPU) { group in
                HStack(spacing: 6) {
                    Text(formatCPU(group.totalCPU))
                        .foregroundStyle(cpuColor(group.totalCPU))
                        .monospacedDigit()
                    MiniBar(fraction: min(group.totalCPU / 100, 1),
                            color: cpuColor(group.totalCPU))
                }
            }
            .width(min: 90, ideal: 115)

            TableColumn("Memory", value: \.totalMemMB) { group in
                Text(formatMB(group.totalMemMB))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Text(monitor.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ToolbarItem(placement: .automatic) {
            Button { monitor.refreshNow() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh now (⌘R)")
            .keyboardShortcut("r", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Picker("Interval", selection: $monitor.refreshInterval) {
                Text("1s").tag(1.0)
                Text("2s").tag(2.0)
                Text("3s").tag(3.0)
                Text("5s").tag(5.0)
                Text("10s").tag(10.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .onChange(of: monitor.refreshInterval) { _, new in
                monitor.setInterval(new)
            }
            .help("Refresh interval")
        }
    }
}

// MARK: - Process Detail Panel

struct ProcessDetailView: View {
    let group: AppGroup
    @State private var sortOrder = [KeyPathComparator(\ProcessInfo.cpu, order: .reverse)]

    private var sorted: [ProcessInfo] {
        group.processes.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.name)
                    .font(.subheadline).bold()
                Text("— \(group.pidCount) process\(group.pidCount == 1 ? "" : "es")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Table(sorted, sortOrder: $sortOrder) {
                TableColumn("PID", value: \.pid) { p in
                    Text("\(p.pid)").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(60)
                TableColumn("Name", value: \.name) { p in
                    Text(p.name).lineLimit(1)
                }
                TableColumn("CPU", value: \.cpu) { p in
                    Text(formatCPU(p.cpu))
                        .monospacedDigit()
                        .foregroundStyle(cpuColor(p.cpu))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(80)
                TableColumn("Memory", value: \.memMB) { p in
                    Text(formatMB(p.memMB))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Helpers

private func cpuColor(_ cpu: Double) -> Color {
    switch cpu {
    case 25...:  return .red
    case 5...:   return .orange
    case 1...:   return Color(red: 0.8, green: 0.7, blue: 0)
    default:     return .secondary
    }
}

struct MiniBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.2))
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7))
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(width: 38, height: 7)
    }
}
