# Rust Phase 1

## Scope

Phase 1 moves the heavy background core into Rust without touching `libsvn` yet.

The goal is not to replicate every TortoiseSVN feature immediately. The goal is to establish a fast, memory-safe backend that can:

- talk to Subversion through the existing `svn` command-line tool
- collect working copy status safely
- maintain the status-refresh architecture outside Finder
- become the backend that Swift UI and Finder integration call into later

## What is implemented now

- a Rust workspace under `rust/`
- `svn_backend`: a typed command-line wrapper for `svn status`, `svn add`, and `svn commit`
- `status_engine`: dirty-root tracking plus badge snapshot generation
- `mtsvn-rs`: a tiny verification CLI that runs the status pipeline
- `RustCommandBridgeSVNClient` in Swift, which calls `mtsvn-rs bridge-status` and `mtsvn-rs bridge-snapshot`
- `StatusCenter.rustPhaseOne(...)`, which is the first concrete Swift-to-Rust wiring path

## Why command-line `svn` first

- lowest integration risk
- fast to iterate on
- easier to debug compatibility issues on macOS
- avoids early FFI and packaging overhead from `libsvn`

## Current crate boundaries

### `svn_backend`

Responsibilities:

- build `svn` command invocations
- normalize working copy paths
- parse `svn status --xml`
- surface typed status entries and command errors

### `status_engine`

Responsibilities:

- track dirty working copy roots
- promote noisy roots into full refresh mode
- turn backend status output into compact badge snapshots
- become the future cache coordinator behind Finder and the standalone app

### `mtsvn-rs`

Responsibilities:

- provide a simple local test harness for the Rust core
- prove that the refresh pipeline works before wiring Swift and XPC layers
- act as the first bridge protocol surface for Swift during development

## Current Swift bridge

The Swift package now talks to Rust through process-based bridging:

- badge-focused queries use `bridge-snapshot`, which exercises the Rust `status_engine`
- broader status queries use `bridge-status`, which returns typed working copy entries
- `StatusCenter` can be initialized directly through `StatusCenter.rustPhaseOne(repositoryRoot:)`
- `StatusServiceHost` now sits above that bridge with SQLite-backed snapshots and dirty-path persistence

This is intentionally a stepping stone. It keeps the integration easy to debug while preserving a clean boundary for a future lower-level FFI or XPC-native bridge.

## Near-term next steps

1. Add persistent cache storage, likely SQLite, behind `status_engine`.
2. Add a stable IPC boundary between Swift and Rust.
3. Route the Swift `StatusCenter` abstraction to this Rust engine.
4. Expand backend coverage for update, revert, log, diff, and shelve-related workflows.
