# Phase 23 Acceptance Checklist

## Registry-Aware Lifecycle Subscriptions

- [x] Skill lifecycle subscriber accepts an optional registry reference and derives additional lifecycle subscription paths from loaded skill hook metadata.
- [x] Subscriber listens for `skill.registry.updated` and refreshes lifecycle subscriptions after registry reloads.
- [x] Refresh flow preserves configured lifecycle signal types and always retains permission-blocked subscription coverage.
- [x] Application wiring passes the runtime skill registry reference into the lifecycle subscriber.

## Validation

- [x] Added observability test that verifies a new frontmatter hook signal type becomes observable after `SkillRegistry.reload/1`.
- [x] Existing lifecycle and permission-blocked observability tests continue to pass under dynamic subscription behavior.
