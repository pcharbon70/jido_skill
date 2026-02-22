# Testing and Quality

This guide defines how runtime behavior is validated locally and in CI.

## Test Suite Map

- `test/jido_skill/config/settings_test.exs`: settings merge, validation, normalization.
- `test/jido_skill/skill_runtime/skill_compiler_test.exs`: frontmatter parser/compiler and module conflict handling.
- `test/jido_skill/skill_runtime/skill_registry_discovery_test.exs`: discovery, local/global override, permissions, registry update publishing.
- `test/jido_skill/skill_runtime/signal_dispatcher_test.exs`: route execution, permission blocking, refresh/migration fallback behavior.
- `test/jido_skill/skill_runtime/hook_emitter_test.exs`: hook precedence, interpolation, disable semantics.
- `test/jido_skill/observability/skill_lifecycle_subscriber_test.exs`: lifecycle subscriptions, telemetry, refresh and migration resilience.
- Contract checks:
  - `test/jido_skill/contracts/settings_schema_test.exs`
  - `test/jido_skill/contracts/skill_frontmatter_schema_test.exs`

## Local Validation Commands

Run the same core checks expected by the project workflow:

```bash
mix test
mix credo --strict
mix dialyzer
```

## Git Hook Gate

The repository pre-commit hook (`.githooks/pre-commit`) enforces:

1. ASDF-managed Erlang/Elixir toolchain availability.
2. Test pass (`mix test`).
3. Credo pass (`mix credo --strict`).
4. Dialyzer pass (`mix dialyzer`).

Recommended one-time setup:

```bash
git config core.hooksPath .githooks
```

## CI and Release Workflows

- CI workflow: `.github/workflows/ci.yml`
  - Reusable lint and test jobs.
  - Test matrix across OTP and Elixir versions.
- Release workflow: `.github/workflows/release.yml`
  - Manual trigger with dry-run controls.
  - Delegates to reusable release workflow.

## Developer Change Checklist

Before opening a PR:

1. Update or add tests for behavior changes.
2. Keep settings/frontmatter schema and runtime validation aligned.
3. Validate signal name/path normalization when touching dispatch or hooks.
4. Run local quality commands and pre-commit hook.
5. Update user/developer docs when contracts or behavior change.
