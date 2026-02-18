# Phase 0 Acceptance Checklist

## Architecture Contract Freeze

- [x] Skill-only runtime scope documented.
- [x] Hook lifecycle limited to `pre` and `post`.
- [x] Signal bus transport (`JidoSignal.Bus`) documented as the only runtime transport.
- [x] Config precedence and conflict rules documented.

## Schema Contracts

- [x] `schemas/settings.schema.json` defines bus and hook configuration.
- [x] `schemas/skill-frontmatter.schema.json` defines skill frontmatter contract.
- [x] Unknown fields are rejected in contract-critical sections.

## Signal Contracts

- [x] Required signal types and payload fields documented.
- [x] Path format and payload merge semantics defined.

## Exit Criteria

Phase 0 is complete when implementation phases can treat these documents and schemas as source-of-truth contracts.
