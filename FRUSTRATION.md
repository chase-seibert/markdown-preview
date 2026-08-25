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

## App Groups break local ad-hoc signing

Adding `com.apple.security.application-groups` to the app and Quick Look
extension makes the Release build require provisioning profiles, which breaks
the project's local `Sign to Run Locally` workflow. Reading the host app's
preference domain directly also fails because its standard preferences live in
the app's private sandbox container. Mirror only the needed value into a
dedicated preference domain, with a `shared-preference.read-write` exception for
the app and a `shared-preference.read-only` exception for the extension.

## `qlmanage -p -o` crashes for the Quick Look extension

On macOS 26, asking `qlmanage` to export this extension's preview reply with
`-p -o` aborts inside ExtensionFoundation with an `NSInvalidArgumentException`
about a nil dictionary key. Use an ordinary fresh preview plus window capture
or extension logging for runtime verification instead.
