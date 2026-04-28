# MacTortoiseSVN

Architecture-first scaffold for a native macOS SVN client inspired by the upstream TortoiseSVN source tree.

## Why this repository starts with architecture

The upstream Windows codebase is clearly split into a few major responsibilities:

- `TortoiseProc`: command routing, dialogs, workflow UI
- `TortoiseShell`: Explorer integration, overlays, context menus
- `TSVNCache`: working copy status cache and directory watching
- `SVN`: the Subversion client abstraction
- `TortoiseMerge`: diff and merge UI
- `SubWCRev`: working copy revision helper tool

The macOS version should keep the same separation of concerns, but avoid the common problems reported in existing macOS competitors:

- Finder extensions that do too much work and stall badge refreshes
- large working copies causing long recursive refreshes and high CPU/RAM usage
- weak partial commit and add-selection workflows
- no standalone client outside Finder
- fragile external diff tool setup
- missing shelve support
- timestamp preservation being ignored

## Repository layout

- `Docs/Architecture.md`: the first-pass target architecture
- `Docs/CompetitiveRequirements.md`: competitor pain points translated into product requirements
- `Docs/RustPhase1.md`: phase-one Rust core plan and crate boundaries
- `Apps/`: host app and extension boundaries
- `Sources/`: buildable Swift package modules for the shared domain and service layer
- `rust/`: phase-one Rust workspace for the background SVN core
- `Tests/`: initial tests for the caching layer

## Key design choices

- Finder Sync stays thin and reads cached badge state over XPC instead of running recursive status scans itself.
- A standalone macOS app is first-class, not a fallback.
- SVN access is abstracted so we can support both bundled and external backends for compatibility.
- The first high-performance backend phase lives in Rust and wraps command-line `svn` before any `libsvn` FFI work.
- Swift now reaches that Rust core through `RustCommandBridgeSVNClient`, and `StatusCenter.rustPhaseOne(...)` is the first ready-to-use integration entry point.
- The first real background service layer now exists as `StatusServiceHost`, backed by a SQLite cache and persistent dirty-path tracking.
- That service layer now includes a real `FSEventsWorkingCopyWatcher`, and the default SQLite cache location is outside the working copy to avoid self-triggered refresh loops.
- `macsvn-statusd` is now a real executable boundary that accepts JSON requests over stdin/stdout and drives `StatusServiceHost`.
- The Rust bridge now supports `status`, `add`, and `commit`, with Swift tests plus real local-SVN integration tests covering the end-to-end path.
- `MacTortoiseSVN` is now a minimal macOS workbench executable with the provided turtle logo, working-copy selection, refresh controls, watcher toggling, and add/commit actions.
- `StatusServiceXPC` now provides the first real NSXPC protocol, client, and bundled service entry point for Finder-facing status reads.
- `FinderSyncBridge` now contains badge resolution and compact context-menu building logic for Finder Sync callers.
- `scripts/build_workbench_app.sh` now assembles a clickable `MacTortoiseSVN.app`, embeds `mtsvn-rs`, and packages the nested status XPC service.
- Large working copy handling is a baseline requirement, not an optimization pass.
- Smart commit selection, add preview, shelve, external diff integration, and timestamp preservation are core features.

## Phase 1 status

1. `StatusServiceHost` is acting as the service-layer core, with SQLite persistence and dirty-root bookkeeping.
2. Real local-SVN integration tests are in place under `Tests/IntegrationTests/RealSVNIntegrationTests.swift`.
3. Swift-to-Rust bridge calls for `add` and `commit` are implemented and exercised in tests.
4. The first standalone macOS UI shell is available as `MacTortoiseSVN`, and it can now be bundled as a local `.app`.
5. The first Finder/XPC bridge layer now exists in code through `FinderSyncBridge`, `StatusServiceXPC`, and `MacSVNStatusXPCService`.

## Build and verify

- Rust tests: `cd rust && /opt/homebrew/bin/cargo test`
- Swift package tests: `env HOME=$PWD/.tmp-home CLANG_MODULE_CACHE_PATH=$PWD/.build/ModuleCache.noindex SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/ModuleCache.noindex swift test`
- App bundle packaging: `./scripts/build_workbench_app.sh`
- Built debug binaries land under `.build/arm64-apple-macosx/debug/`:
- `MacTortoiseSVN`
- `MacSVNStatusXPCService`
- `macsvn-statusd`
- `mtsvn`
- Packaged app bundle lands under `dist/MacTortoiseSVN.app`

## Remaining gaps after phase 1

- There is still no full Xcode workspace for the app, Finder Sync extension, Quick Actions target, and signing/distribution pipeline.
- Finder Sync now has shared bridge code and an extension source skeleton, but it is not yet built and installed as a real Finder extension bundle.
- Shelve and unshelve are still intentionally stubbed on the Rust bridge.
- External diff launching, timestamp preservation policy enforcement, and backend compatibility switching still need real implementation work.
- Performance validation on very large working copies is still missing; the architecture is in place, but benchmark and stress runs have not been added yet.
