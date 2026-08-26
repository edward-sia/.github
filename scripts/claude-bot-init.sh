#!/usr/bin/env bash
# Install the on-demand @claude bot into a repository.
#
#   claude-bot-init                 # current repo (from cwd)
#   claude-bot-init owner/repo      # a specific repo
#
# Writes .github/workflows/claude.yml from the canonical template in
# edward-sia/.github, then makes sure CLAUDE_CODE_OAUTH_TOKEN is set.
#
# The review rubric is deliberately NOT installed. The workflow fetches it
# from edward-sia/.github at run time, so it stays a single source of truth.

set -euo pipefail

TEMPLATE_REPO="edward-sia/.github"
TEMPLATE_URL="https://raw.githubusercontent.com/${TEMPLATE_REPO}/main/templates/claude.yml"
WORKFLOW_PATH=".github/workflows/claude.yml"
SECRET_NAME="CLAUDE_CODE_OAUTH_TOKEN"

die() { printf 'claude-bot-init: %s\n' "$*" >&2; exit 1; }

command -v gh   >/dev/null 2>&1 || die "gh is required but not installed"
command -v curl >/dev/null 2>&1 || die "curl is required but not installed"

repo="${1:-}"
if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
    || die "not inside a GitHub repo — pass one explicitly: claude-bot-init owner/repo"
fi

gh api "repos/${repo}" >/dev/null 2>&1 || die "cannot access repo '${repo}'"
branch=$(gh api "repos/${repo}" -q .default_branch)

printf '→ %s (default branch: %s)\n' "$repo" "$branch"

# --- 1. workflow file -------------------------------------------------------
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 "$TEMPLATE_URL" -o "$tmp" \
  || die "could not fetch the workflow template from ${TEMPLATE_URL}"
[ -s "$tmp" ] || die "fetched workflow template is empty"

content=$(base64 < "$tmp" | tr -d '\n')

# An existing file needs its blob sha to update in place.
sha=$(gh api "repos/${repo}/contents/${WORKFLOW_PATH}?ref=${branch}" -q .sha 2>/dev/null || true)

if [ -n "$sha" ]; then
  remote=$(gh api "repos/${repo}/contents/${WORKFLOW_PATH}?ref=${branch}" -q .content \
           | tr -d '\n' | base64 --decode)
  if [ "$remote" = "$(cat "$tmp")" ]; then
    printf '  workflow already up to date\n'
  else
    gh api --method PUT "repos/${repo}/contents/${WORKFLOW_PATH}" \
      -f message="ci: update the on-demand @claude bot workflow" \
      -f content="$content" -f sha="$sha" -f branch="$branch" >/dev/null
    printf '  workflow updated\n'
  fi
else
  gh api --method PUT "repos/${repo}/contents/${WORKFLOW_PATH}" \
    -f message="ci: add the on-demand @claude bot" \
    -f content="$content" -f branch="$branch" >/dev/null
  printf '  workflow added\n'
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
  printf '\u2713 %s ready. Comment on a PR: @claude review this PR per .github/claude-review.md\n' "$repo"
else
  printf '! %s: workflow installed, but the bot will fail until you run:\n' "$repo"
  printf '    gh secret set %s -R %s\n' "$SECRET_NAME" "$repo"
  exit 2
fi
