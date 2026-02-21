# Phase 49 Acceptance Checklist

## Lifecycle Startup With Registry Initialization Failures

- [x] Lifecycle subscriber startup no longer fails when registry-derived hook subscription paths are invalid.
- [x] Subscriber startup no longer fails when initial registry `list_skills`/`hook_defaults` reads fail.
- [x] Subscriber initializes with base subscriptions and remains subscribed to registry updates under startup fallback conditions.

## Validation

- [x] Added lifecycle regression proving startup succeeds with invalid registry hook paths and recovers after registry metadata is corrected.
- [x] Added lifecycle regression proving startup succeeds when registry reads fail at init and recovers registry-derived subscriptions after refresh.
