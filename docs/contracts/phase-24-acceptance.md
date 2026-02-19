# Phase 24 Acceptance Checklist

## Hook Enabled Subscription Filtering

- [x] Registry-derived lifecycle subscriptions ignore hook signal types when the corresponding hook is explicitly disabled (`enabled: false`).
- [x] Lifecycle subscription refresh adds the hook signal type when the same hook is later enabled and registry reload is triggered.
- [x] Existing configured and contract-required subscriptions (`skill/pre`, `skill/post`, and `skill/permission/blocked`) remain unaffected.

## Validation

- [x] Added observability regression test for disabled hook signal types staying unsubscribed after reload.
- [x] Added observability regression test that verifies enabled transition activates subscription after reload.
