# Phase 77 Acceptance Checklist

## Lifecycle Telemetry Across Settings-Driven Permission Reload

- [x] Lifecycle subscriber receives `skill.permission.blocked` telemetry when dispatcher blocks execution under `ask` permissions.
- [x] Permission-blocked telemetry stops after `SkillRegistry.reload/1` refreshes settings permissions and route permission status transitions from `ask` to `allowed`.
- [x] Permission-blocked telemetry remains active when settings reload fails and cached `ask` permissions are retained.
- [x] Telemetry metadata for permission-blocked signals preserves `skill_name`, normalized `route`, `reason`, `tools`, and `timestamp`.

## Validation

- [x] Added lifecycle integration regression proving blocked telemetry is emitted before reload and stops after settings permission refresh allows execution.
- [x] Added lifecycle integration regression proving blocked telemetry continues when settings reload fails with invalid JSON.
