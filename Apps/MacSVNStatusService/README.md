# MacSVNStatusService

Background status and operations service.

Expected responsibilities:

- own FSEvents watchers and dirty-root queues
- keep a persistent status index
- publish badge snapshots to Finder integration targets
- coordinate cancellable long-running SVN operations

This target is the main guardrail against Finder stalls, CPU spikes, and crash propagation.

Current implementation status in the Swift package:

- `StatusServiceHost` provides refresh, snapshot, dirty-path, and eviction APIs
- `SQLiteStatusCacheStore` persists badge snapshots and dirty roots
- `FSEventsWorkingCopyWatcher` provides the first real recursive file-system event source
- Rust remains the backend for live SVN status calculation
- `StatusServiceXPC` now exposes the first NSXPC protocol, client, and listener delegate
- `MacSVNStatusXPCService` is the first bundled XPC service executable
- `Apps/MacSVNStatusService/Info.plist` is ready for packaging into the app bundle
