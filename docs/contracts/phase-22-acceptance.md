# Phase 22 Acceptance Checklist

## Configurable Lifecycle Subscriptions

- [x] Skill lifecycle subscriber accepts configurable lifecycle signal types via startup options.
- [x] Application wiring passes lifecycle signal types from loaded settings hooks into the subscriber.
- [x] Subscriber still includes `skill.permission.blocked` telemetry subscription independent of hook signal type configuration.
- [x] Empty or invalid configured lifecycle signal type lists fall back to default `skill/pre` and `skill/post` subscriptions.

## Validation

- [x] Added subscriber test coverage for custom lifecycle signal subscriptions.
- [x] Added subscriber test coverage for empty-list fallback to default lifecycle subscriptions.
