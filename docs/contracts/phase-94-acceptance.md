# Phase 94 Acceptance Checklist

## Dispatcher Startup Bus-Name Resolution on Refresh Enabled

- [x] Dispatcher resolves registry `:bus_name` during startup when `refresh_bus_name` is enabled and starts route subscriptions on that bus.
- [x] Dispatcher dispatches routed signals on the refreshed startup bus immediately after initialization.
- [x] Dispatcher does not dispatch routed signals on the configured startup bus after successful startup migration.

## Validation

- [x] Added dispatcher integration regression proving startup attaches route subscriptions to the refreshed registry bus and executes routes only from that bus.
