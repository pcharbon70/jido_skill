# Skill Compilation and Loading

This guide explains how `SKILL.md` files become executable runtime modules.

## Frontmatter Parse Model

`JidoSkill.SkillRuntime.Skill.from_markdown/1` parses markdown in stages:

1. Split YAML frontmatter from body.
2. Parse root keys and `jido` section with indentation-sensitive rules.
3. Validate schema-like constraints in Elixir.
4. Normalize actions/router/hooks.
5. Compile module with metadata, docs body, and helper functions.

Accepted root keys:

- `name`
- `description`
- `version`
- `allowed-tools`
- `jido`

Accepted `jido` keys:

- `skill_module` (optional override)
- `actions` (required)
- `router` (required)
- `hooks` (`pre`/`post` only)

## Validation Rules

- `version` must match `x.y.z`.
- Action references must be valid module references and loadable.
- Router paths must match `^[a-z0-9_-]+(?:/[a-z0-9_-]+)*$`.
- Router action references must map to declared actions.
- Hook names are limited to `pre` and `post`.
- Hook keys are limited to `enabled`, `signal_type`, `bus`, `data`.

## Module Naming and Conflicts

- If `jido.skill_module` is present, the compiler uses that module name.
- Otherwise a deterministic generated module name is derived from skill source path hash under `JidoSkill.CompiledSkills`.
- If a module already exists and was generated from the same source path, recompilation is allowed.
- If a module already exists from a different source or non-generated runtime module, compilation fails with conflict errors.

## Discovery and Merge

`SkillRegistry` discovers files from:

- `~/.jido_code/skills/**/SKILL.md`
- `.jido_code/skills/**/SKILL.md`

Discovery behavior:

- Files are sorted for deterministic load order.
- Duplicates in the same scope keep first entry and log warnings.
- Local scope overrides global scope by skill name.

## Reload Semantics

`SkillRegistry.reload/0` does all of the following:

1. Attempts to reload settings from settings files when present.
2. Keeps cached hook defaults/permissions/bus if reload validation fails.
3. Rebuilds skill registry entries from disk.
4. Publishes `skill.registry.updated` with sorted skill names and count.

Registry update publication targets both previous and refreshed bus names when bus changes to avoid losing dependent subscription refresh events.
