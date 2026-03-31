import Foundation

func formatCPU(_ v: Double) -> String { String(format: "%.1f%%", v) }

func formatMB(_ mb: Double) -> String {
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    return String(format: "%.0f MB", mb)
}
