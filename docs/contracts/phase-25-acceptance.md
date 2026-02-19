# Phase 25 Acceptance Checklist

## Hook Enabled Boolean Semantics

- [x] Registry-derived hook enablement checks correctly honor `enabled: false` when hook metadata uses atom keys.
- [x] Hook enablement lookups support both atom and string key formats without boolean coercion regressions.
- [x] Disabled-hook observability regression checks actively probe over time after reload to avoid async false positives.

## Validation

- [x] Added lifecycle subscriber regression coverage proving disabled hook signal types remain unsubscribed under repeated post-reload publishing.
- [x] Existing enabled-transition reload test continues to verify subscription activation once hook is enabled.
