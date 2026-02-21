# Phase 76 Acceptance Checklist

## Dispatcher Permission Continuity Across Settings Reload

- [x] Dispatcher reflects settings-backed permission changes after `SkillRegistry.reload/1` refreshes registry permissions.
- [x] A route that was executable before reload is blocked after reload when refreshed settings change its `permission_status` to `ask` or `denied`.
- [x] Dispatcher preserves prior permission behavior when registry settings reload fails and cached registry permissions are retained.
- [x] Permission-blocked signal payloads (`skill.permission.blocked`) continue to include skill name, normalized route, reason, and tools.

## Validation

- [x] Added dispatcher integration regression proving execution-to-blocked transition after settings permission refresh on registry reload.
- [x] Added dispatcher integration regression proving blocked behavior remains unchanged when settings reload fails with invalid JSON.
