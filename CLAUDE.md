# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open in Xcode:
```bash
open SwiftyMon.xcodeproj
```

Type-check all source files without a full build (fast syntax/type validation):
```bash
swiftc -sdk $(xcrun --sdk macosx --show-sdk-path) \
  -target arm64-apple-macosx14.0 -typecheck -swift-version 5 \
  SwiftyMon/Models.swift SwiftyMon/Formatters.swift \
  SwiftyMon/ProcessMonitor.swift SwiftyMon/ContentView.swift \
  SwiftyMon/SwiftyMonApp.swift
```

Full build from CLI (requires Xcode license accepted via `sudo xcodebuild -license accept`):
```bash
xcodebuild -project SwiftyMon.xcodeproj -scheme SwiftyMon \
  -destination "platform=macOS" build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Architecture

The app is a single-window macOS SwiftUI utility with no dependencies beyond the standard SDK. There are no tests.

**Data flow:** `ProcessMonitor` (the model) → `ContentView` (main table) → `ProcessDetailView` (per-process panel shown when a row is selected).

**`ProcessMonitor.swift`** — `@Observable` class that owns all data fetching. A repeating `Timer` calls `triggerRefresh()` on each tick, which cancels any in-flight `Task` and starts a new one. Inside the task, `ps` and `nettop` are run sequentially as subprocesses via `Process` + `withCheckedThrowingContinuation` (dispatched to `DispatchQueue.global(qos: .utility)`). Network rates are computed by diffing cumulative `nettop` byte counts between samples and dividing by elapsed time.

**`Models.swift`** — Two plain structs: `ProcessInfo` (one OS process) and `AppGroup` (all processes sharing the same binary name). `AppGroup` exposes computed totals (`totalCPU`, `totalMemMB`, `totalNetIn`, `totalNetOut`) used directly as `TableColumn` sort key paths.

**`ContentView.swift`** — SwiftUI `Table` bound to `[AppGroup]` with `KeyPathComparator`-based column sorting. Selecting a row shows `ProcessDetailView` (another `Table` for individual `ProcessInfo` rows) in a panel below. `cpuColor()` and `MiniBar` provide the inline CPU visualisation.

**`Formatters.swift`** — Three free functions: `formatCPU`, `formatMB`, `formatBPS`. All formatting lives here.

## Key Constraints

- **Sandbox is disabled** (`SwiftyMon.entitlements` sets `com.apple.security.app-sandbox = false`). This is required to spawn `ps` and `nettop` as subprocesses. Do not re-enable sandbox without replacing the subprocess approach with an XPC privileged helper.
- **GPU / Neural Engine data is not available** without `sudo powermetrics`. The app does not attempt privilege escalation.
- **Swift language mode is 6.0** (`SWIFT_VERSION = 6.0`). `ProcessMonitor` is `@MainActor` to satisfy strict concurrency — all properties live on the main actor. The subprocess helpers (`runPS`, `runCommand`) are `nonisolated` since they only use local state, and the `Timer` callback uses `MainActor.assumeIsolated` (safe because the timer is always added to `RunLoop.main`).
- `nettop` is not used — on macOS 26 it hangs indefinitely when spawned as a subprocess (likely requires additional entitlements or a different invocation). Network bandwidth data is omitted for now. If re-adding it, do not use `process.waitUntilExit()` without a timeout.
