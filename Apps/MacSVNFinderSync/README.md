# MacSVNFinderSync

Thin Finder Sync extension.

Expected responsibilities:

- fetch cached badge state
- expose a compact context menu
- open the main app for complex workflows

This target must not run recursive status scans or own large in-memory working copy models.

Current scaffold status:

- `FinderSyncBridge` now resolves badge identifiers from cached snapshots
- `FinderSyncBridge` now builds the compact context menu model for selected paths
- `Apps/MacSVNFinderSync/Sources/MacSVNFinderSyncExtension.swift` contains the first extension-side XPC call path
- `Apps/MacSVNFinderSync/Info.plist` is ready for a future real extension bundle target
