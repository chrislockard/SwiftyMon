import Foundation

func formatCPU(_ v: Double) -> String { String(format: "%.1f%%", v) }

func formatMB(_ mb: Double) -> String {
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    return String(format: "%.0f MB", mb)
}

func formatBPS(_ bps: Double) -> String {
    if bps <= 0 { return "—" }
    let kb = bps / 1_024
    let mb = kb / 1_024
    let gb = mb / 1_024
    if gb >= 1 { return String(format: "%.1f GB/s", gb) }
    if mb >= 1 { return String(format: "%.1f MB/s", mb) }
    if kb >= 1 { return String(format: "%.1f KB/s", kb) }
    return String(format: "%.0f B/s", bps)
}
