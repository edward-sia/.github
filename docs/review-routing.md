# Claude Review Routing

This document is the canonical model-selection policy for the shared Claude
review workflow.

## When Reviews Run

- A same-repository pull request triggers one automatic review when opened.
- A manual `@claude` comment or submitted review can request another run.
- Fork PRs are skipped because their `pull_request` workflows cannot receive
  `CLAUDE_CODE_OAUTH_TOKEN`.
- Adding a label after opening does not trigger another automatic review. Add
  the label and use a manual `@claude review this PR` request to apply it.

## Model Selection

The first matching rule wins:

1. Exactly one override label selects the model: `claude:sonnet` selects
   Sonnet and `claude:opus` selects Opus. Both labels make the run fail closed.
2. A manual request containing `opus`, `deep`, `deeply`, `thorough`,
   `thoroughly`, `widely`, `extensive`, or `extensively` selects Opus.
3. More than 25 changed files or more than 800 additions plus deletions
   selects Opus.
4. Opus reviews capability-granting or high-blast-radius paths:
   - identity, access-control, secrets, certificates, or cryptography;
   - payments and billing; databases, schemas, and migrations;
   - CI definitions, custom GitHub Actions, or `CODEOWNERS`;
   - infrastructure, deployment, containers, and common IaC directories;
   - dependency manifests and lockfiles, environment configuration, and
     agent/MCP configuration; or
   - files beneath `docs/superpowers/specs/` or `docs/superpowers/plans/`.
5. Sonnet reviews all other pull requests, including ordinary documentation.

Opus runs for up to 30 minutes with a 1M-token context. Sonnet runs for up to
15 minutes with a 1M-token context. The workflow reports the selected model
and reason in its Actions notice.

## Path-Baseline Provenance

This is a conservative cross-repository baseline, not a claim that one list is
complete for every product. It covers control paths repeatedly protected in
production review workflows: executable GitHub Actions, infrastructure,
migrations, ownership policy, container definitions, and dependency files.
Those categories are grounded in [GitHub's secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use),
[GitHub's pull-request security guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target),
and [StepSecurity Secure Repo](https://github.com/step-security/secure-repo).

Add a repository-specific capability path when its change can grant access,
execute trusted automation, deploy production infrastructure, or irreversibly
alter data. Every addition needs a representative execution case in
`scripts/test-review-profile.sh`.

## Change Safety

After changing this policy, add or adjust a real execution case in
`scripts/test-review-profile.sh`, then run:

```bash
scripts/test-review-profile.sh
scripts/test-review-context.sh
actionlint templates/claude.yml .github/workflows/claude-on-demand.yml
```
