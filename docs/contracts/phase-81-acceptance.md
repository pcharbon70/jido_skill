# Phase 81 Acceptance Checklist

## Dispatcher Signal Bus Continuity Across Settings Reload

- [x] Dispatcher routes dispatch traffic on the cached startup bus before settings-driven registry reload.
- [x] Dispatcher migrates registry-update and route subscriptions to the refreshed signal bus after `SkillRegistry.reload/1` updates `signal_bus.name`.
- [x] Dispatcher removes stale subscriptions from the prior bus once migration to the refreshed bus succeeds.
- [x] Dispatcher preserves cached bus dispatch behavior when refreshed-bus migration fails and the target bus is unavailable.

## Validation

- [x] Added dispatcher integration regression proving route dispatch transitions from the cached startup bus to the settings-reloaded bus after registry reload.
- [x] Added dispatcher integration regression proving cached bus dispatch remains active when migration to a refreshed but unavailable bus fails.
