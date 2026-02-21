# Phase 75 Acceptance Checklist

## Skill Registry Reload Permission Refresh

- [x] `SkillRegistry.reload/1` refreshes cached permissions from settings files when configured settings paths are present.
- [x] Reload reclassifies discovered skill entries using refreshed settings permissions so `permission_status` reflects updated `allow`/`deny`/`ask` rules.
- [x] Reload keeps existing cached permissions when settings files are missing and no settings reload source is available.
- [x] Reload keeps existing cached permissions when settings files exist but loading or validation fails.
- [x] Existing registry update signal publication behavior remains unchanged.

## Validation

- [x] Added registry discovery regression verifying reload updates skill `permission_status` from settings-backed permission changes.
- [x] Added registry discovery regression verifying reload preserves cached permissions when local settings content is invalid JSON.
