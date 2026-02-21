# Phase 79 Acceptance Checklist

## Lifecycle Hook Subscription Continuity Across Settings Reload

- [x] Lifecycle subscriber observes inherited lifecycle hook signals from cached hook defaults before settings-driven registry reload.
- [x] Lifecycle subscriber refreshes inherited hook signal subscriptions after `SkillRegistry.reload/1` updates hook defaults from settings files.
- [x] Lifecycle subscriber removes stale inherited hook subscriptions once refreshed hook defaults replace prior signal types.
- [x] Lifecycle subscriber preserves cached inherited hook subscriptions when settings reload fails and registry retains prior hook defaults.

## Validation

- [x] Added lifecycle integration regression proving inherited hook subscription path transitions from cached to settings-reloaded hook signal types.
- [x] Added lifecycle integration regression proving inherited hook subscription paths remain unchanged when settings reload fails with invalid JSON.
