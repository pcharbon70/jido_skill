# ADR 0002: Configuration Precedence And Conflict Rules

## Status
Accepted

## Context
The architecture uses global and local settings plus per-skill frontmatter overrides. Deterministic merge and conflict behavior is required for repeatable runtime behavior.

## Decision

1. Settings precedence: `.jido_code/settings.json` overrides `~/.jido_code/settings.json`.
2. Hook precedence: `jido.hooks.pre|post` in skill frontmatter override global `hooks.pre|post`.
3. Disable semantics: `enabled: false` in frontmatter disables that hook for the skill.
4. Skill name conflict resolution: local skill wins over global skill when names collide.
5. Unknown keys in settings/frontmatter contract sections are rejected by schema validation.

## Consequences

1. Skill behavior is portable across environments with clear local override semantics.
2. Hot reload and conflict handling are deterministic.
3. Validation failures happen early at load time instead of runtime.
