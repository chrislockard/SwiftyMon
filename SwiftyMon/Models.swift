import Foundation

struct ProcessInfo: Identifiable, Hashable {
    let pid: Int
    let name: String
    var cpu: Double      // %
    var memMB: Double    // MB
    var netInBPS: Double // bytes/sec
    var netOutBPS: Double

    var id: Int { pid }
}

struct AppGroup: Identifiable {
    let name: String
    var processes: [ProcessInfo]

    var id: String { name }
    var totalCPU: Double    { processes.reduce(0) { $0 + $1.cpu } }
    var totalMemMB: Double  { processes.reduce(0) { $0 + $1.memMB } }
    var totalNetIn: Double  { processes.reduce(0) { $0 + $1.netInBPS } }
    var totalNetOut: Double { processes.reduce(0) { $0 + $1.netOutBPS } }
    var pidCount: Int       { processes.count }
}
