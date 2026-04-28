# Rust Core

Phase-one Rust workspace for the macOS SVN client.

This stage intentionally wraps the existing `svn` command-line tool instead of binding `libsvn`.

## Crates

- `svn_backend`: typed wrapper around command-line `svn`
- `status_engine`: dirty-root tracking and badge snapshot generation
- `mtsvn-rs`: tiny verification CLI for local testing

## Why this phase exists

- get a safe and fast background core running first
- avoid early FFI complexity with `libsvn`
- keep compatibility flexible across bundled or system Subversion installs
- prove the status-refresh architecture before wiring macOS UI targets to it

