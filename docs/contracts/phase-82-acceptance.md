# Phase 82 Acceptance Checklist

## Lifecycle Signal Bus Continuity Across Settings Reload

- [x] Lifecycle subscriber emits telemetry on the cached startup bus before settings-driven registry reload.
- [x] Lifecycle subscriber migrates registry-update and lifecycle signal subscriptions to the refreshed bus after `SkillRegistry.reload/1` updates `signal_bus.name`.
- [x] Lifecycle subscriber retires stale old-bus subscriptions once refreshed-bus migration succeeds.
- [x] Lifecycle subscriber preserves cached bus subscriptions and telemetry behavior when refreshed-bus migration fails.

## Validation

- [x] Added lifecycle integration regression proving lifecycle telemetry transitions from cached startup bus subscriptions to refreshed-bus subscriptions after registry reload.
- [x] Added lifecycle integration regression proving lifecycle telemetry remains on cached-bus subscriptions when migration to a refreshed but unavailable bus fails.
