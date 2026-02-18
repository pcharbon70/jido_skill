# ADR 0001: Skill-Only Runtime Scope

## Status
Accepted

## Context
The architecture in `notes/research/skills.md` defines a narrowed runtime model. We need explicit scope constraints before implementation to avoid reintroducing unsupported concepts.

## Decision
The v1 runtime is constrained to the following:

1. Execution model is skill-only (`Jido.Skill` + `Jido.Action`).
2. Hook model supports only two lifecycle points: `pre` and `post`.
3. Transport is exclusively `JidoSignal.Bus` (`jido_signal`).
4. No agent, command, or extension abstractions are included in runtime APIs.
5. Skill definitions are loaded from markdown with YAML frontmatter.

## Consequences

1. Runtime surface area is smaller and easier to validate.
2. Operator behavior is predictable because all lifecycle events flow through one signal bus.
3. Feature requests for additional hook types must be ADR-backed and deferred beyond v1.
4. Documentation and schemas can be strict because unsupported concepts are intentionally out of scope.
