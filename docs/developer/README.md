# Developer Guides

This directory contains developer-facing architecture and implementation guides for the current `jido_skill` runtime.

## Guide Index

- `docs/developer/architecture-overview.md`: supervision topology, startup flow, and system boundaries.
- `docs/developer/components-reference.md`: component-by-component responsibilities, APIs, and invariants.
- `docs/developer/skill-compilation-and-loading.md`: frontmatter parsing, validation, compilation, and discovery/reload behavior.
- `docs/developer/signal-lifecycle-and-fallbacks.md`: route dispatch flow, lifecycle/permission signals, and resilience fallback behavior.
- `docs/developer/testing-and-quality.md`: test suite map, local quality gates, CI, and release automation.

## Scope

These guides describe the runtime currently implemented in this repository:

- Skill-only architecture (`Jido.Action` execution through compiled skill modules).
- Signal transport on `Jido.Signal.Bus`.
- Optional lifecycle hooks limited to `pre` and `post`.
- No agent, command, or extension runtime abstractions.
