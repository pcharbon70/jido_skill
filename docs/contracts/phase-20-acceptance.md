# Phase 20 Acceptance Checklist

## Signal Source Contract Alignment

- [x] Hook lifecycle signals emit slash-delimited source paths using `/hooks/{signal_type}`.
- [x] Permission-blocked signals emit slash-delimited source paths using `/permissions/{signal_type}`.
- [x] Bus routing remains dot-delimited and unchanged for internal dispatch compatibility.

## Validation

- [x] Added hook emitter tests asserting source path contract for slash and dot signal type inputs.
- [x] Added signal dispatcher tests asserting permission-blocked source path contract.
