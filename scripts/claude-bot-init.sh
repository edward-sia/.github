#!/usr/bin/env bash
# Install the on-demand @claude bot into a repository.
#
#   claude-bot-init                 # current repo (from cwd)
#   claude-bot-init owner/repo      # a specific repo
#
# Writes .github/workflows/claude.yml from the canonical template in
# edward-sia/.github, then makes sure CLAUDE_CODE_OAUTH_TOKEN is set.
#
# The review rubric is deliberately NOT installed. The workflow downloads it
# from edward-sia/.github at run time, so it stays a single source of truth.
#
# This pushes over git rather than the contents API on purpose. Writing a file
# under .github/workflows/ through the API needs the `workflow` OAuth scope,
# which `gh auth login` does not grant by default — and GitHub reports the
# refusal as a bare 404. A git push carries no such restriction.

set -euo pipefail

TEMPLATE_REPO="edward-sia/.github"
TEMPLATE_URL="https://raw.githubusercontent.com/${TEMPLATE_REPO}/main/templates/claude.yml"
WORKFLOW_PATH=".github/workflows/claude.yml"
SECRET_NAME="CLAUDE_CODE_OAUTH_TOKEN"

die() { printf 'claude-bot-init: %s\n' "$*" >&2; exit 1; }

command -v gh   >/dev/null 2>&1 || die "gh is required but not installed"
command -v git  >/dev/null 2>&1 || die "git is required but not installed"
command -v curl >/dev/null 2>&1 || die "curl is required but not installed"

repo="${1:-}"
if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
    || die "not inside a GitHub repo — pass one explicitly: claude-bot-init owner/repo"
fi

gh api "repos/${repo}" --silent >/dev/null 2>&1 || die "cannot access repo '${repo}'"
branch=$(gh api "repos/${repo}" -q .default_branch)

printf '→ %s (default branch: %s)\n' "$repo" "$branch"

work=$(mktemp -d)
tmpl=$(mktemp)
trap 'rm -rf "$work" "$tmpl"' EXIT

# --- 1. workflow file -------------------------------------------------------
# Cache-bust: raw.githubusercontent.com serves with max-age=300, so a template
# edited in the last five minutes would otherwise install stale.
curl -fsSL --retry 3 -H 'Cache-Control: no-cache' \
  "${TEMPLATE_URL}?t=$(date +%s)" -o "$tmpl" \
  || die "could not fetch the workflow template from ${TEMPLATE_URL}"
[ -s "$tmpl" ] || die "fetched workflow template is empty"

gh repo clone "$repo" "$work/repo" -- --depth 1 --branch "$branch" --quiet 2>/dev/null \
  || die "could not clone ${repo}"

dest="$work/repo/${WORKFLOW_PATH}"
if [ -f "$dest" ] && cmp -s "$tmpl" "$dest"; then
  printf '  workflow already up to date\n'
else
  if [ -f "$dest" ]; then verb=update; done_msg="workflow updated"
  else                    verb=add;    done_msg="workflow added"; fi

  mkdir -p "$(dirname "$dest")"
  cp "$tmpl" "$dest"
  git -C "$work/repo" add "$WORKFLOW_PATH"
  git -C "$work/repo" commit -q -m "ci: ${verb} the on-demand @claude bot"

  # A repo owner can push straight through their own branch protection. Doing
  # that silently would be the wrong default, so open a PR instead and let the
  # repo's own rules decide when it lands.
  protected=$(gh api "repos/${repo}/branches/${branch}" -q .protected 2>/dev/null || echo false)
  if [ "$protected" = "true" ]; then
    head="claude-bot-init"
    git -C "$work/repo" branch -m "$head"
    git -C "$work/repo" push -q -u origin "$head" \
      || die "could not push branch ${head} to ${repo}"
    url=$(gh pr create -R "$repo" --base "$branch" --head "$head" \
            --title "ci: ${verb} the on-demand @claude bot" \
            --body "Adds the shared \`@claude\` bot workflow. The review rubric is not committed here — the workflow downloads it from [${TEMPLATE_REPO}](https://github.com/${TEMPLATE_REPO}) at run time." )
    printf '  %s branch is protected — opened %s\n' "$branch" "$url"
  else
    git -C "$work/repo" push -q origin "$branch" \
      || die "could not push to ${repo} — check your SSH key and write access"
    printf '  %s\n' "$done_msg"
  fi
fi

# --- 2. secret --------------------------------------------------------------
# Secrets are write-only, so an existing one cannot be read back — only listed.
secret_ok=0
if gh secret list -R "$repo" 2>/dev/null | grep -q "^${SECRET_NAME}[[:space:]]"; then
  printf '  %s already set\n' "$SECRET_NAME"
  secret_ok=1
elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN" | gh secret set "$SECRET_NAME" -R "$repo"
  printf '  %s set from the environment\n' "$SECRET_NAME"
  secret_ok=1
elif [ -t 0 ]; then
  printf '  %s is not set. Paste it now (input is hidden), or Ctrl-C to skip:\n' "$SECRET_NAME"
  if gh secret set "$SECRET_NAME" -R "$repo"; then secret_ok=1; fi
else
  # No terminal to prompt on. Say so and leave, rather than hanging on stdin.
  printf '  %s is not set, and there is no terminal to prompt on.\n' "$SECRET_NAME"
fi

if [ "$secret_ok" -eq 1 ]; then
  printf '✓ %s ready. Comment on a PR: @claude review this PR per .github/claude-review.md\n' "$repo"
else
  printf '! %s: workflow installed, but the bot will fail until you run:\n' "$repo"
  printf '    gh secret set %s -R %s\n' "$SECRET_NAME" "$repo"
  exit 2
fi
