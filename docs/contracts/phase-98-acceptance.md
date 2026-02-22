# Phase 98 Acceptance Checklist

## Dispatcher Startup Bus-Name Call-Exception Repeated Refresh Fallback and Recovery

- [x] Dispatcher keeps configured startup bus subscriptions when registry `:bus_name` lookup raises call exceptions during startup.
- [x] Dispatcher preserves cached startup bus route subscriptions when repeated refreshes continue raising `:bus_name` call exceptions.
- [x] Dispatcher migrates route and registry-update subscriptions to the refreshed bus after startup/refresh `:bus_name` call-exception lookups recover.

## Validation

- [x] Added dispatcher integration regression proving startup `:bus_name` call-exception fallback remains stable across two consecutive refresh call exceptions and migrates after recovery.
