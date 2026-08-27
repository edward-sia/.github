# .github

Shared GitHub configuration for `edward-sia` repositories.

## What lives here

| Path | What it is | How repos get it |
| --- | --- | --- |
| `claude-review.md` | The PR review rubric for the `@claude` bot | Downloaded at run time. Never copied into a repo. |
| `.github/workflows/claude-on-demand.yml` | The bot's whole job: checkout, rubric fetch, Claude invocation | Referenced at run time (`uses: ...@main`). Never copied into a repo. |
| `templates/claude.yml` | A thin caller: triggers + `@claude` guard + a `uses:` line | Copied into each repo once, by the script below. |
| `scripts/claude-bot-init.sh` | Installs the bot into a repo | Run once per repo. |

## Why the bot lives here instead of in each repo

The rubric and the job are the parts that change. Each repo's `claude.yml` is
only a caller: it declares the comment triggers and points at
`claude-on-demand.yml` in this repo. Actions resolves that reference fresh
from `main` on every run, so editing the rubric or the job here changes the
bot in every repo, with no PRs to open and no copies to drift.

The caller is the part that does not change, so it is a normal copy.

The trigger guard stays in the caller on purpose: a job-level `if` in the
calling repo means comments without `@claude` never create a run at all,
instead of logging a skipped run for every comment in every repo.

If the rubric ever moves or is deleted, `curl -f` fails the job. The bot stops
rather than quietly reviewing against nothing.

**A rubric edit takes up to 5 minutes to reach the runners.**
`raw.githubusercontent.com` serves with `cache-control: max-age=300`. Nothing
breaks — a review started inside that window just uses the previous rubric.
Edits to `claude-on-demand.yml` are not cached at all: Actions reads the
workflow from `main` directly when the run starts.

**The rubric is fetched into `RUNNER_TEMP`, not into the checkout.** The
action switches to the PR branch mid-run, and on a branch that still tracks
`.github/claude-review.md` from before the rubric moved here, git refuses to
overwrite an untracked file at that path and the run dies
(cuddly-succotash run 33063471676). Claude is pointed at the temp copy
through the system prompt, so the trigger comment no longer needs to name a
path.

## Adding the bot to a repo

```bash
claude-bot-init owner/repo   # or just `claude-bot-init` from inside the repo
```

Then comment on any PR:

> @claude review this PR

The older phrasing `@claude review this PR per .github/claude-review.md`
still works — the system prompt tells Claude where that file lives now.

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
