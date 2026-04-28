# MacSVNApp

Primary standalone macOS client.

Expected responsibilities:

- commit, update, log, diff, merge, browse, and shelve workflows
- settings for backend compatibility, diff tools, timestamp policy, and performance limits
- progress, cancellation, and error recovery UI for large operations

This target should stay UI-focused and call shared services rather than owning repository scanning logic directly.
