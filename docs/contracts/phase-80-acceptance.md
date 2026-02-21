# Phase 80 Acceptance Checklist

## Skill Registry Reload Signal Bus Refresh

- [x] `SkillRegistry.reload/1` refreshes cached signal bus name from settings files when configured settings are present and valid.
- [x] Registry update publication (`skill.registry.updated`) uses the refreshed bus name after settings-driven reload.
- [x] Reload keeps existing cached signal bus name when settings files are missing or settings loading fails.
- [x] Existing skill discovery, hook defaults refresh, and permission refresh behavior remain unchanged.

## Validation

- [x] Added registry discovery regression verifying `bus_name` transitions from cached startup value to settings-reloaded signal bus value and registry update publishes on the refreshed bus.
- [x] Added registry discovery regression verifying cached `bus_name` remains unchanged when settings reload fails with invalid JSON.
