# Phase 28 Acceptance Checklist

## Registry Hook Inheritance Subscription Parity

- [x] Registry-derived lifecycle subscriptions honor frontmatter hook `enabled` inheritance from global hook defaults.
- [x] Frontmatter hooks that explicitly set `enabled: true` can inherit global `signal_type` values for observability subscriptions.
- [x] Frontmatter hooks that do not override a globally disabled hook remain unsubscribed, even when `signal_type` is present.

## Validation

- [x] Added lifecycle subscriber regression test proving inherited global `signal_type` is subscribed when frontmatter explicitly enables the hook.
- [x] Added lifecycle subscriber regression test proving disabled global default remains unsubscribed unless frontmatter overrides enablement.
