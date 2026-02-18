# Phase 13 Acceptance Checklist

## Frontmatter Contract Hardening

- [x] Compiler rejects unknown keys in the `jido` frontmatter section.
- [x] Compiler validates router path format (`{segment}/{segment}` with lower-case, digits, `_`, and `-`).
- [x] Compiler validates router action references use module-like identifiers.

## Hook Validation

- [x] Compiler rejects unknown keys inside `jido.hooks.pre` and `jido.hooks.post`.
- [x] Compiler validates optional hook fields (`enabled`, `signal_type`, `bus`, `data`) when present.
- [x] Compiler validates hook signal type and bus format with the same path/name rules used by settings.

## Validation

- [x] Added compiler tests for unknown `jido` keys.
- [x] Added compiler tests for invalid router paths.
- [x] Added compiler tests for unknown hook keys and invalid hook signal types.
