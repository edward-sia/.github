# .github

Shared GitHub configuration for `edward-sia` repositories. Today that is one
thing: an automatic and on-demand `@claude` reviewer for pull requests.

## What it does

Every newly opened pull request from a branch in an installed repository is
reviewed automatically. You can also request or repeat a review with a comment:

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
| `scripts/test-review-profile.sh` | Checks model routing against comments, labels, PR size, and changed paths. |
| `scripts/test-review-context.sh` | Checks PR metadata retrieval for each supported event shape. |
| `docs/review-routing.md` | The model-selection policy and its operational limits. |

**In each repo.** Installed once by the script.

| Path | What it is |
| --- | --- |
| `.github/workflows/claude.yml` | A copy of the template. Automatically reviews newly opened same-repository PRs and accepts `@claude` requests. |
| `CLAUDE_CODE_OAUTH_TOKEN` secret | GitHub has no user-level Actions secrets, so every repo needs its own. |

The rubric is never copied into a repo.

## Who

- A same-repository PR starts one automatic review when it opens. Anyone who can comment on an issue or PR can also trigger a manual run. There is no user allow-list.
- Whoever has push access to a repo installs the bot there.
- Whoever can push to `main` here changes the rubric and the job for every repo.

## How it is triggered

The caller listens for a newly opened pull request, a comment on an issue or
PR, a comment on a PR diff, and a submitted PR review. A newly opened PR from
the repository starts a review automatically. The other three events require
`@claude` in the body, so unrelated comments never start a run.

Fork PRs are deliberately skipped. GitHub withholds the OAuth secret from a
fork-triggered `pull_request` workflow; allowing it through would create a
failing run instead of a review.

When the guard passes, the shared job:

1. Checks out the repo.
2. Downloads `claude-review.md` from this repo's `main` into the runner's temp directory.
3. Picks a model from the trigger, pull-request metadata, and changed paths (next section).
4. Runs `anthropics/claude-code-action` with that model and a system prompt that points at the rubric.

The older phrasing `@claude review this PR per .github/claude-review.md` still
works. The system prompt tells Claude where that file lives now.

## Picking the review model

The router is deterministic and writes its reason to the Actions-run notice.
It does not use one model to decide whether another should review. The full
policy is in [`docs/review-routing.md`](docs/review-routing.md).

| Profile | Model flag | Time limit | Example |
| --- | --- | --- | --- |
| Opus | `opus[1m]` | 30 min | An auth change or a Superpowers spec/plan |
| Sonnet (default) | `sonnet` | 15 min | A normal application or documentation change |

Priority order: `claude:sonnet` or `claude:opus` labels; an explicit manual
request containing `opus`, `deep`, `deeply`, `thorough`, `thoroughly`,
`widely`, `extensive`, or `extensively`; more than 25 changed files or 800
changed lines; sensitive paths and Superpowers specs/plans; then Sonnet.

Labels affect manual re-reviews immediately. Adding a label after a PR has
opened does not create a second automatic review; use `@claude review this PR`
to run the selected override.

The `[1m]` suffix keeps Opus at a 1M-token context window. Without it Opus runs
at 200K, which a review of a few thousand changed lines can exceed. Sonnet
always runs at 1M.

After changing the router, run:

```bash
scripts/test-review-profile.sh
scripts/test-review-context.sh
actionlint templates/claude.yml .github/workflows/claude-on-demand.yml
```

## Install with an agent

This section is for an agent such as Claude Code that has been told to install
the bot with no human in the loop. Follow it as written.

**Preconditions.** Check all three before doing anything. If one fails, stop
and report which one. Do not try to repair it.

1. `gh auth status` exits 0 for github.com, and that account can push to the target repo.
2. `git` and `curl` are on the PATH.
3. `CLAUDE_CODE_OAUTH_TOKEN` is set in the environment. You cannot create it. `claude setup-token` needs a browser login, so a human generates it once and stores it where you can read it.

**Install one repo.** Replace `owner/repo`.

```bash
tmp=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/edward-sia/.github/main/scripts/claude-bot-init.sh -o "$tmp" && bash "$tmp" owner/repo </dev/null; echo "exit=$?"
```

`</dev/null` closes stdin so the script never waits on a prompt. It takes the
token from the environment instead.

**Read the exit code.**

| Exit | Meaning | Next step |
| --- | --- | --- |
| 0 | The workflow is on the default branch and the secret is set. | Run the verify commands. |
| 2 | The workflow is installed but the token was not in the environment. | Precondition 3 failed. Report it. |
| anything else | The script stopped before the workflow landed. | Report the `claude-bot-init:` line from stderr. |

**If the default branch is protected.** The script prints a line ending in a
PR URL, then exits 0 with the workflow on a `claude-bot-init` branch instead of
the default branch. Merge that PR:

```bash
gh pr merge <url> --squash --delete-branch
```

If the merge is refused because the branch needs a review you cannot give,
report the PR URL and stop. The bot does not work until that PR lands.

**Verify.** Both commands must succeed.

```bash
gh api repos/owner/repo/contents/.github/workflows/claude.yml --jq .path
```

```bash
gh secret list -R owner/repo | grep -q '^CLAUDE_CODE_OAUTH_TOKEN[[:space:]]'
```

**Every repo at once.** Same preconditions. Archived repos are skipped.

```bash
tmp=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/edward-sia/.github/main/scripts/claude-bot-init.sh -o "$tmp" && gh repo list edward-sia --limit 200 --no-archived --json nameWithOwner -q '.[].nameWithOwner' | while read -r r; do bash "$tmp" "$r" </dev/null || echo "FAILED $r exit=$?"; done
```

Report every `FAILED` line and every PR URL the script printed.

**Smoke test.** Only if the repo already has an open PR. Do not open one for
this.

```bash
gh pr comment <number> -R owner/repo --body "@claude review this PR"
```

Within a minute, `gh run list -R owner/repo --workflow "Claude Code" --limit 1`
shows a new run.

## Install by hand

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
