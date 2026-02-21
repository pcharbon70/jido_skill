# Phase 6 Acceptance Checklist

## Skill Dispatch Runtime

- [x] Compiled skills match incoming signal routes against frontmatter `jido.router` definitions.
- [x] Matched routes return `{:ok, %Jido.Instruction{...}}` with signal payload mapped into instruction params.
- [x] Unmatched routes return `{:skip, signal}` without side effects.

## Lifecycle Hook Integration

- [x] `handle_signal/2` emits pre hook signals for matched routes using frontmatter-over-global hook precedence.
- [x] `transform_result/3` emits post hook signals with derived status (`"ok"` or `"error"`).
- [x] Route metadata in post hook payload is resolved from compiled router entries.

## Validation

- [x] Added runtime dispatch tests for matched route instruction creation and pre-hook emission.
- [x] Added runtime dispatch tests for unmatched route skip behavior.
- [x] Added runtime dispatch tests for post-hook emission status and global-hook fallback behavior.
