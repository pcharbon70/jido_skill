# Phase 36 Acceptance Checklist

## Lifecycle Telemetry Timestamp Propagation

- [x] Lifecycle subscriber telemetry metadata exposes top-level `timestamp` extracted from signal payload data.
- [x] Permission-blocked telemetry metadata surfaces `timestamp` when provided by dispatcher payloads.
- [x] Existing lifecycle metadata fields (`type`, `source`, `bus`, `phase`, `skill_name`, `route`, `status`, `reason`, `tools`) remain unchanged.

## Validation

- [x] Added subscriber regression test asserting lifecycle signal payload `timestamp` is propagated to telemetry metadata.
- [x] Updated permission-blocked telemetry regression to assert `timestamp` presence in metadata.
