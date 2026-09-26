#!/usr/bin/env bash
# Usage: scripts/test-review-context.sh [path/to/claude-on-demand.yml]

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
workflow=${1:-"$here/../.github/workflows/claude-on-demand.yml"}
script=$(awk '
  $0 ~ "^[[:space:]]*id: pr-context[[:space:]]*$" { in_step = 1; next }
  in_step && /^[[:space:]]*run: \|[[:space:]]*$/ { in_run = 1; next }
  in_run {
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    match($0, /^[[:space:]]*/)
    if (indent == 0) indent = RLENGTH
    if (RLENGTH < indent) exit
    print substr($0, indent + 1)
  }
' "$workflow")

if [ -z "$script" ]; then
  echo "FAIL: no step with id \"pr-context\" and a run: | block in $workflow" >&2
  exit 1
fi

pass=0; fail=0

check_context() {
  local desc=$1 event_name=$2 issue_number=$3 pull_request_number=$4 want_number=$5
  local work out log
  work=$(mktemp -d); out="$work/output"; log="$work/gh.log"
  if ! PATH="$here/test-fixtures:$PATH" GH_LOG="$log" RUNNER_TEMP="$work" EVENT_NAME="$event_name" ISSUE_NUMBER="$issue_number" PULL_REQUEST_NUMBER="$pull_request_number" GITHUB_REPOSITORY='owner/repo' GITHUB_OUTPUT="$out" bash --noprofile --norc -eo pipefail -c "$script" >/dev/null 2>"$work/error"; then
    printf 'FAIL  %s\n      step exited non-zero: %s\n' "$desc" "$(cat "$work/error")"
    fail=$((fail + 1)); rm -rf "$work"; return
  fi

  local labels_path paths_path
  labels_path=$(sed -n 's/^labels_path=//p' "$out")
  paths_path=$(sed -n 's/^paths_path=//p' "$out")
  if grep -Fq "/repos/owner/repo/pulls/$want_number" "$log" &&
     grep -Fxq 'changed_files=2' "$out" &&
     grep -Fxq 'additions=3' "$out" &&
     grep -Fxq 'deletions=5' "$out" &&
     [ -f "$labels_path" ] &&
     [ -f "$paths_path" ] &&
     grep -Fxq 'claude:opus' "$labels_path" &&
     grep -Fxq 'src/auth.ts' "$paths_path" &&
     grep -Fxq 'EOF' "$paths_path"; then
    printf 'ok    %s\n' "$desc"; pass=$((pass + 1))
  else
    printf 'FAIL  %s\n      context did not fetch PR %s or emit its metadata\n' "$desc" "$want_number"
    fail=$((fail + 1))
  fi
  rm -rf "$work"
}

check_context "pull_request uses its pull request number" pull_request '' 42 42
check_context "a PR conversation comment uses its issue number" issue_comment 42 '' 42
check_context "a submitted PR review uses its pull request number" pull_request_review '' 42 42
check_context "a PR diff comment uses its pull request number" pull_request_review_comment '' 42 42

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
