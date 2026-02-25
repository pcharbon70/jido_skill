# Phase 121 Acceptance Checklist

## Dispatcher Refresh Bus-Name Exit Registry Subscription Fallback and Recovery

- [x] Dispatcher preserves the cached registry-update subscription when refresh-time registry `:bus_name` calls exit.
- [x] Dispatcher keeps route dispatch active on the configured bus while repeated refresh attempts continue returning `:bus_name` exits.
- [x] Dispatcher rebinds the registry-update subscription on the refreshed bus after `:bus_name` exits stop and refresh succeeds.

## Validation

- [x] Added dispatcher integration regression proving repeated refresh-time `:bus_name` exits keep the cached registry subscription stable and rebind after recovery.
