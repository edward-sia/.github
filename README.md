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

## Adding the bot to a repo

```bash
claude-bot-init owner/repo   # or just `claude-bot-init` from inside the repo
```

Then comment on any PR:

> @claude review this PR per .github/claude-review.md

## The one manual step

GitHub has no user-level Actions secrets, so `CLAUDE_CODE_OAUTH_TOKEN` must be
set on every repo individually. The script prompts for it, or reads it from a
`CLAUDE_CODE_OAUTH_TOKEN` environment variable if you have one exported.

Generate a token with `claude setup-token`.

## What this repo cannot do

Workflow templates that appear in the Actions tab are an **organization**
feature. This account is a personal one, so new repos do not pick up workflows
automatically — `claude-bot-init` is the substitute. Community health files
(`SECURITY.md`, issue templates, `CONTRIBUTING.md`) *do* apply account-wide
from here if you add them.
