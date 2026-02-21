# Phase 21 Acceptance Checklist

## Signal Contract Observability

- [x] Skill lifecycle telemetry metadata includes signal `source` for downstream contract-aware observability.
- [x] Telemetry tests use slash-delimited hook and permission source paths that match the signal contract.
- [x] Skill registry reload tests assert `skill.registry.updated` source path remains `/skill_registry`.

## Validation

- [x] Updated lifecycle subscriber tests to assert `source` metadata for pre/post and permission-blocked signals.
- [x] Updated registry discovery tests to assert registry update source path contract.
