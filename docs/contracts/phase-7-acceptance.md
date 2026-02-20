# Phase 7 Acceptance Checklist

## GitHub Workflow Baseline

- [x] Repository defines CI workflow for pull requests and pushes to `main`.
- [x] CI workflow delegates lint and test jobs to reusable workflows in `agentjido/github-actions`.
- [x] CI workflow test job configures OTP/Elixir version matrices through workflow inputs.

## Release Automation

- [x] Repository defines a manual release workflow using `workflow_dispatch`.
- [x] Release workflow exposes dry-run and test-skip controls for safe release execution.
- [x] Release workflow grants `contents: write` permissions and inherits repository secrets.

## Validation

- [x] Added `.github/workflows/ci.yml` and `.github/workflows/release.yml`.
- [x] Workflow files reference shared reusable workflows from `agentjido/github-actions`.
