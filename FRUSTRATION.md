# Frustration Log

Record recurring build or tooling failure modes here when they are discovered.

## SwiftPM inside the managed filesystem sandbox

`swift test` can fail before reading the manifest with `sandbox-exec:
sandbox_apply: Operation not permitted`; SwiftPM tries to create its own nested
sandbox even though the project directory is writable. Run the same Make target
with sandbox escalation rather than changing package code or cache locations.

## Swift 6 nonisolated deinitializers

An `@MainActor` document cannot access a non-`Sendable` watcher from its
nonisolated `deinit`. Keep watcher cleanup in the watcher itself and mark the
queue-confined watcher `@unchecked Sendable` when its synchronization is
explicit.

## `swift format lint --strict` rejects the repository's existing style

The strict formatter reports indentation errors across nearly every existing
Swift line because its configured style differs from the repository's
four-space indentation. Use the compiler, `git diff --check`, and targeted
formatting for changed code instead of treating strict lint output as actionable.
