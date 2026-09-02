# .github

Shared GitHub configuration for `edward-sia` repositories. Today that is one
thing: an on-demand `@claude` reviewer for pull requests.

## What it does

Comment on any pull request in an installed repo:

> @claude review this PR

A GitHub Actions job checks out the PR, downloads the shared review rubric from
this repo, and runs Claude Code with that rubric as its instructions. Claude
replies on the PR.

## Why it lives here

The rubric and the job are the parts that change. Each repo holds only a small
caller workflow that points at the job in this repo. Actions reads the job
fresh from `main` on every run, and the job downloads the rubric fresh too. So
an edit here changes the bot in every repo at once, with nothing to merge and
no copies to drift.

## What lives where

**In this repo.** Edited here, read at run time.

| Path | What it is |
| --- | --- |
| `claude-review.md` | The review rubric. Downloaded on every run. |
| `.github/workflows/claude-on-demand.yml` | The job. Each repo calls it with `uses:`. |
| `templates/claude.yml` | The caller workflow copied into each repo. |
| `scripts/claude-bot-init.sh` | Installs the caller and the secret into a repo. |
| `scripts/test-review-profile.sh` | Checks the model-picking step against sample comments. |

**In each repo.** Installed once by the script.

| Path | What it is |
| --- | --- |
| `.github/workflows/claude.yml` | A copy of the template. Declares the triggers, requires `@claude` in the comment, and calls the shared job. |
| `CLAUDE_CODE_OAUTH_TOKEN` secret | GitHub has no user-level Actions secrets, so every repo needs its own. |

The rubric is never copied into a repo.

## Who

- Anyone who can comment on an issue or PR can trigger a run. There is no user allow-list.
- Whoever has push access to a repo installs the bot there.
- Whoever can push to `main` here changes the rubric and the job for every repo.

## How it is triggered

The caller listens for three events: a comment on an issue or PR, a comment on
a PR diff, and a submitted PR review. Its job-level `if` requires the text
`@claude` in the body. Other comments never start a run, so they do not even
appear as skipped runs.

When the guard passes, the shared job:

1. Checks out the repo.
2. Downloads `claude-review.md` from this repo's `main` into the runner's temp directory.
3. Picks a model from the trigger comment (next section).
4. Runs `anthropics/claude-code-action` with that model and a system prompt that points at the rubric.

The older phrasing `@claude review this PR per .github/claude-review.md` still
works. The system prompt tells Claude where that file lives now.

## Picking the model from the comment

If the trigger comment contains any of these words, as a whole word in any
case, the run uses Opus. Otherwise it uses Sonnet.

`opus`, `deep`, `deeply`, `thorough`, `thoroughly`, `widely`, `extensive`,
`extensively`

| Profile | Model flag | Time limit | Example |
| --- | --- | --- | --- |
| Opus | `opus[1m]` | 30 min | `@claude review this PR thoroughly` |
| Sonnet (default) | `sonnet` | 15 min | `@claude review this PR` |

Whole-word matching means "DeepSeek" and "thoroughness" still get Sonnet. The
chosen profile appears as a notice on the Actions run.

The `[1m]` suffix keeps Opus at a 1M-token context window. Without it Opus runs
at 200K, which a review of a few thousand changed lines can exceed. Sonnet
always runs at 1M.

The keyword list is one line in `claude-on-demand.yml`. After editing it, run
`scripts/test-review-profile.sh`.

## How to install it in a repo

You need `gh`, `git`, `curl`, and SSH push access to the repo.

```bash
claude-bot-init owner/repo
```

`claude-bot-init` is `scripts/claude-bot-init.sh` from this repo, on your PATH.
With no argument it targets the repo you are inside. The script:

1. Commits `templates/claude.yml` as `.github/workflows/claude.yml`, or reports it is already up to date.
2. Pushes to the default branch. If that branch is protected, it opens a PR instead. A repo owner can push through their own branch protection, and doing that silently would be the wrong default.
3. Sets `CLAUDE_CODE_OAUTH_TOKEN` from an existing secret, your environment, or a prompt, in that order. Generate a token with `claude setup-token`.

It exits `2` if the workflow is installed but the secret is still missing, so a
scripted rollout can tell "done" from "done except the token". Re-run it to
pick up a changed template.

## When a change takes effect

| You edit | It reaches repos |
| --- | --- |
| `claude-review.md` | On the next run, up to 5 minutes later. `raw.githubusercontent.com` caches for 300 seconds. |
| `claude-on-demand.yml` | On the next run. Actions reads it from `main` with no cache. |
| `templates/claude.yml` | After you re-run the installer on each repo. |

## Non-obvious choices

**The rubric goes into `RUNNER_TEMP`.** The action switches to the PR branch
mid-run. On a branch that still tracks `.github/claude-review.md` from before
the rubric moved here, git refuses to overwrite an untracked file at that path
and the run dies (cuddly-succotash run 33063471676).

**A missing rubric stops the bot.** The download uses `curl -f`. If the file is
moved or deleted, the job fails instead of reviewing against nothing.

**The installer pushes over git.** Writing under `.github/workflows/` through
the REST contents API needs the `workflow` OAuth scope. `gh auth login` does
not grant it, and the API reports the refusal as a bare `404`. To use the API
path anyway, run `gh auth refresh -h github.com -s workflow`.

**Claude's output stream shows only on private repos.** It carries file
contents, diffs and MCP payloads, so the job turns it on only where the
Actions log is private.

## What this repo cannot do

Workflow templates in the Actions tab are an organization feature, and this is
a personal account. New repos do not pick up the bot on their own. The
installer is the substitute. Community health files (`SECURITY.md`,
`CONTRIBUTING.md`, issue templates) do apply account-wide from here if you add
them.
