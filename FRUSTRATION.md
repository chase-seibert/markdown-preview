# Frustration Log

Record recurring build or tooling failure modes here when they are discovered.

## SwiftPM inside the managed filesystem sandbox

`swift test` can fail before reading the manifest with `sandbox-exec:
sandbox_apply: Operation not permitted`; SwiftPM tries to create its own nested
sandbox even though the project directory is writable. Run the same Make target
with sandbox escalation rather than changing package code or cache locations.
