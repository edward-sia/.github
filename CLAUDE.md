# Shared Claude Review Configuration

This repository owns a reusable workflow, its caller template, and the shared
review rubric for `edward-sia` repositories.

## Verify Changes

```bash
scripts/test-review-profile.sh
scripts/test-review-context.sh
actionlint templates/claude.yml .github/workflows/claude-on-demand.yml
```

## Maintenance Rules

- Keep `templates/claude.yml` and `.github/workflows/claude-on-demand.yml`
  compatible: the template owns events and permissions; the shared workflow
  owns runtime behavior.
- A template change reaches existing repositories only after
  `scripts/claude-bot-init.sh` is re-run for each one.
- The rubric is downloaded at run time, so its changes apply on the next run.
- Keep model routing deterministic. Its policy lives in
  [`docs/review-routing.md`](docs/review-routing.md); add a sample to
  `scripts/test-review-profile.sh` for every new branch.
