# Signal Contracts (Phase 0)

## Scope
These contracts define the minimum signal surface for the initial implementation.

## Signal Types

| Type | Producer | Required Data | Source |
|------|----------|---------------|--------|
| `skill/pre` | Hook emitter | `phase`, `skill_name`, `route`, `timestamp` | `/hooks/{signal_type}` |
| `skill/post` | Hook emitter | `phase`, `skill_name`, `route`, `status`, `timestamp` | `/hooks/{signal_type}` |
| `skill/registry/updated` | Skill registry | `skills`, `count` | `/skill_registry` |

## Path Format

1. Signal type paths are slash-delimited lower-case identifiers.
2. Recommended pattern: `{domain}/{entity}/{event}`.
3. Allowed characters per segment: `a-z`, `0-9`, `_`.

## Payload Rules

1. Hook payload is merged from template data and runtime data.
2. Runtime fields (`phase`, `skill_name`, `route`, `status`, `timestamp`) take precedence over template collisions.
3. `status` is required for `skill/post` and omitted for `skill/pre`.
