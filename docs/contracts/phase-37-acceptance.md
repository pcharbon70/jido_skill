# Phase 37 Acceptance Checklist

## Post Hook Route Fidelity For Shared Actions

- [x] Skill runtime stores the matched router path in instruction context during `handle_signal/2`.
- [x] `transform_result/3` prefers the matched route from instruction context when emitting post-hook lifecycle signals.
- [x] Existing post-hook route derivation fallback remains unchanged when instruction context does not include a matched route.

## Validation

- [x] Updated runtime dispatch regression to assert instruction context includes `jido_skill_route`.
- [x] Added regression test proving post-hook `route` stays correct when multiple routes map to the same action module.
