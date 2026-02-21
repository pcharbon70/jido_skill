# Phase 87 Acceptance Checklist

## Lifecycle Startup Bus-Name Resolution and Migration Fallback

- [x] Lifecycle subscriber resolves registry `:bus_name` during startup when `refresh_bus_name` is enabled and starts lifecycle subscriptions on that bus.
- [x] Lifecycle subscriber falls back to configured bus subscriptions when startup migration target is unavailable, then migrates after registry bus recovery.
- [x] Lifecycle subscriber preserves refresh-time `:bus_name` call-exception behavior after startup bus resolution is enabled.

## Validation

- [x] Added lifecycle integration regression proving startup attaches lifecycle subscriptions to refreshed registry bus when available.
- [x] Added lifecycle integration regression proving startup migration fallback to configured bus when refreshed bus is unavailable and successful migration after recovery.
- [x] Updated lifecycle call-exception refresh regressions to account for startup bus lookup ordering while preserving cached-bus guarantees.
