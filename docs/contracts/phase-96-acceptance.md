# Phase 96 Acceptance Checklist

## Dispatcher Startup Invalid Bus-Name Repeated Refresh Fallback and Recovery

- [x] Dispatcher keeps configured startup bus subscriptions when registry `:bus_name` lookup is invalid during startup.
- [x] Dispatcher preserves cached startup bus route subscriptions when repeated refreshes continue returning invalid `:bus_name` values.
- [x] Dispatcher migrates route and registry-update subscriptions to the refreshed bus after invalid `:bus_name` startup/refresh lookups recover.

## Validation

- [x] Added dispatcher integration regression proving startup invalid `:bus_name` fallback remains stable across two consecutive invalid refreshes and migrates after recovery.
