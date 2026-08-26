# .github

Shared GitHub configuration for `edward-sia` repositories.

## What lives here

| Path | What it is | How repos get it |
| --- | --- | --- |
| `claude-review.md` | The PR review rubric for the `@claude` bot | Downloaded at run time. Never copied into a repo. |
| `templates/claude.yml` | The bot's workflow file | Copied into each repo once, by the script below. |
| `scripts/claude-bot-init.sh` | Installs the bot into a repo | Run once per repo. |

## Why the rubric is downloaded instead of copied

The rubric is the part that changes. Each repo's workflow fetches it into
`.github/claude-review.md` on the runner just before Claude starts, so editing
this one file changes how the bot reviews in every repo, with no PRs to open
and no copies to drift.

The workflow file is the part that does not change, so it is a normal copy.

If the rubric ever moves or is deleted, `curl -f` fails the job. The bot stops
rather than quietly reviewing against nothing.

**A rubric edit takes up to 5 minutes to reach the runners.**
`raw.githubusercontent.com` serves with `cache-control: max-age=300`. Nothing
breaks — a review started inside that window just uses the previous rubric.

## Adding the bot to a repo

```bash
claude-bot-init owner/repo   # or just `claude-bot-init` from inside the repo
```

Then comment on any PR:

> @claude review this PR per .github/claude-review.md

If the default branch is protected, the script opens a pull request instead of
pushing to it. A repo owner can push through their own branch protection, and
doing that silently would be the wrong default.

## The one manual step

GitHub has no user-level Actions secrets, so `CLAUDE_CODE_OAUTH_TOKEN` must be
set on every repo individually. The script prompts for it, or reads it from a
`CLAUDE_CODE_OAUTH_TOKEN` environment variable if you have one exported.

Generate a token with `claude setup-token`.

The script exits `2` when it installed the workflow but the secret is still
missing, so a scripted rollout can tell "done" from "done except the token".

## Why the installer pushes over git

Writing a file under `.github/workflows/` through the REST contents API needs
the `workflow` OAuth scope, which `gh auth login` does not grant by default.
Without it the API returns a bare `404` that looks like a missing repo. A git
push over SSH carries no such restriction, so the script clones and pushes.

To use the API path instead, run `gh auth refresh -h github.com -s workflow`.

## What this repo cannot do

Workflow templates that appear in the Actions tab are an **organization**
feature. This account is a personal one, so new repos do not pick up workflows
automatically — `claude-bot-init` is the substitute. Community health files
(`SECURITY.md`, issue templates, `CONTRIBUTING.md`) *do* apply account-wide
from here if you add them.
