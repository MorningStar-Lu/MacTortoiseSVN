# Competitive Requirements

This document converts the current macOS SVN competitor pain points into explicit product requirements for this project.

## Performance

### Reported competitor pain

- badge and overlay refreshes can take tens of minutes on large working copies
- refresh loops consume too much CPU and RAM
- large commits can freeze or crash
- memory leaks make the whole machine sluggish

### Requirements

- Finder integration must never perform recursive repository scans directly.
- Status refresh must be driven by a shared cache and incremental invalidation.
- Long-running refreshes and commits must be cancelable.
- The background status service must have explicit concurrency and memory ceilings.
- Large working copies must be a primary design target, not an afterthought.

## Workflow quality

### Reported competitor pain

- partial commit selection is awkward and error-prone
- `Add...` can recurse too aggressively
- shelve is missing
- external diff tool integration is fragile
- timestamp preservation is missing
- Finder is the only real client surface

### Requirements

- Commit UI must default to changed paths and support path-tree selection cleanly.
- Add flows must always show a preview with depth controls before a recursive add.
- Shelve and unshelve must be first-class workflows.
- Built-in presets for BBEdit and Beyond Compare should work without manual argument discovery.
- Users must be able to preserve file modification times after checkout and update.
- The app must remain fully useful as a standalone client even if Finder integration is disabled.

## Stability and compatibility

### Reported competitor pain

- newer macOS versions sometimes break overlays or context menus
- Finder integration can fail unless users set up manual workarounds
- SVN backend compatibility may differ between bundled and system tools
- licensing limits create friction for serious users

### Requirements

- Provide both Finder Sync and Quick Actions integration surfaces.
- Keep core workflows available in the standalone app even when Finder surfaces fail.
- Abstract the SVN backend so users can switch compatibility modes when needed.
- Avoid artificial working copy limits in the product model.

## Product positioning

### What this means for scope

- This should not be "just a Finder extension."
- Performance, reliability, and workflow quality are the main wedge against the existing macOS competition.
- The architecture must stay friendly to future cross-platform reuse of the shared backend and workflow modules.
