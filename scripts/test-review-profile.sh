#!/usr/bin/env bash
# Usage: scripts/test-review-profile.sh [path/to/claude-on-demand.yml]

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
workflow=${1:-"$here/../.github/workflows/claude-on-demand.yml"}
export PATH="/usr/bin:$PATH"

run_block_of_step() {
  local step_id=$1 file=$2
  awk -v id="$step_id" '
    $0 ~ "^[[:space:]]*id: " id "[[:space:]]*$" { in_step = 1; next }
    in_step && /^[[:space:]]*run: \|[[:space:]]*$/ { in_run = 1; next }
    in_run {
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      match($0, /^[[:space:]]*/)
      if (indent == 0) indent = RLENGTH
      if (RLENGTH < indent) exit
      print substr($0, indent + 1)
    }
  ' "$file"
}

script=$(run_block_of_step profile "$workflow")
if [ -z "$script" ]; then
  echo "FAIL: no step with id \"profile\" and a run: | block in $workflow" >&2
  exit 1
fi

pass=0; fail=0

check() {
  check_with_context "$1" "$2" "$3" "$4" "" 0 0 ""
}

check_with_context() {
  local desc=$1 want_model=$2 want_timeout=$3 text=$4 labels=$5 changed_files=$6 changed_lines=$7 paths=$8
  local out; out=$(mktemp)
  if ! TRIGGER_TEXT="$text" PR_LABELS="$labels" PR_CHANGED_FILES="$changed_files" PR_ADDITIONS="$changed_lines" PR_DELETIONS=0 PR_PATHS="$paths" GITHUB_OUTPUT="$out" bash --noprofile --norc -eo pipefail -c "$script" >/dev/null 2>"$out.err"; then
    printf 'FAIL  %s\n      step exited non-zero: %s\n' "$desc" "$(cat "$out.err")"
    fail=$((fail + 1)); rm -f "$out" "$out.err"; return
  fi
  local got_model got_timeout
  got_model=$(sed -n 's/^model=//p' "$out")
  got_timeout=$(sed -n 's/^timeout=//p' "$out")
  rm -f "$out" "$out.err"
  if [ "$got_model" = "$want_model" ] && [ "$got_timeout" = "$want_timeout" ]; then
    printf 'ok    %s\n' "$desc"; pass=$((pass + 1))
  else
    printf 'FAIL  %s\n      want model=%s timeout=%s\n      got  model=%s timeout=%s\n' \
      "$desc" "$want_model" "$want_timeout" "$got_model" "$got_timeout"
    fail=$((fail + 1))
  fi
}

check_with_file_context() {
  local desc=$1 want_model=$2 want_timeout=$3 labels=$4 paths=$5
  local work out
  work=$(mktemp -d); out="$work/output"
  printf '%s\n' "$labels" > "$work/labels"
  printf '%s\n' "$paths" > "$work/paths"
  if ! TRIGGER_TEXT='' PR_LABELS='' PR_PATHS='' PR_LABELS_FILE="$work/labels" PR_PATHS_FILE="$work/paths" PR_CHANGED_FILES=2 PR_ADDITIONS=40 PR_DELETIONS=0 GITHUB_OUTPUT="$out" bash --noprofile --norc -eo pipefail -c "$script" >/dev/null 2>"$work/error"; then
    printf 'FAIL  %s\n      step exited non-zero: %s\n' "$desc" "$(cat "$work/error")"
    fail=$((fail + 1)); rm -rf "$work"; return
  fi
  local got_model got_timeout
  got_model=$(sed -n 's/^model=//p' "$out")
  got_timeout=$(sed -n 's/^timeout=//p' "$out")
  if [ "$got_model" = "$want_model" ] && [ "$got_timeout" = "$want_timeout" ]; then
    printf 'ok    %s\n' "$desc"; pass=$((pass + 1))
  else
    printf 'FAIL  %s\n      want model=%s timeout=%s\n      got  model=%s timeout=%s\n' \
      "$desc" "$want_model" "$want_timeout" "$got_model" "$got_timeout"
    fail=$((fail + 1))
  fi
  rm -rf "$work"
}

check_rejected() {
  local desc=$1 text=$2 labels=$3 changed_files=$4 changed_lines=$5 paths=$6
  local out; out=$(mktemp)
  if TRIGGER_TEXT="$text" PR_LABELS="$labels" PR_CHANGED_FILES="$changed_files" PR_ADDITIONS="$changed_lines" PR_DELETIONS=0 PR_PATHS="$paths" GITHUB_OUTPUT="$out" bash --noprofile --norc -eo pipefail -c "$script" >/dev/null 2>"$out.err"; then
    printf 'FAIL  %s\n      expected the profile step to reject the input\n' "$desc"
    fail=$((fail + 1))
  else
    printf 'ok    %s\n' "$desc"
    pass=$((pass + 1))
  fi
  rm -f "$out" "$out.err"
}

OPUS='opus[1m]'; OPUS_T=30
SONNET='sonnet';  SONNET_T=15

check "plain review request is the sonnet profile"      "$SONNET" "$SONNET_T" "@claude review this PR"
check "empty trigger text is the sonnet profile"        "$SONNET" "$SONNET_T" ""
check "'opus' selects the opus profile"                 "$OPUS"   "$OPUS_T"   "@claude please review this PR with opus"
check "'deep' selects the opus profile"                 "$OPUS"   "$OPUS_T"   "@claude please deep review this PR"
check "'deeply' selects the opus profile"               "$OPUS"   "$OPUS_T"   "@claude review this PR deeply"
check "'thorough' selects the opus profile"             "$OPUS"   "$OPUS_T"   "@claude do a thorough review of this PR"
check "'thoroughly' selects the opus profile"           "$OPUS"   "$OPUS_T"   "@claude please thoroughly review this PR"
check "'widely' selects the opus profile"               "$OPUS"   "$OPUS_T"   "@claude please widely review this PR"
check "'extensive' selects the opus profile"            "$OPUS"   "$OPUS_T"   "@claude extensive review please"
check "'extensively' selects the opus profile"          "$OPUS"   "$OPUS_T"   "@claude please extensively review this PR"
check "keywords match regardless of case"               "$OPUS"   "$OPUS_T"   "@claude DEEP review this PR"
check "keyword on a later line still counts"            "$OPUS"   "$OPUS_T"   $'@claude review this PR\n\nbe thorough, it touches auth'
check "keyword followed by punctuation still counts"    "$OPUS"   "$OPUS_T"   "@claude review this PR (opus)."
check "'DeepSeek' is not the keyword 'deep'"            "$SONNET" "$SONNET_T" "@claude review this PR, we moved to DeepSeek"
check "'thoroughness' is not the keyword 'thorough'"    "$SONNET" "$SONNET_T" "@claude review this PR, thoroughness matters"
check "'wide' alone is not a keyword"                   "$SONNET" "$SONNET_T" "@claude review this PR, the table is wide"

check_with_context "a claude:sonnet label overrides a deep-review request" \
  "$SONNET" "$SONNET_T" "@claude review this PR thoroughly" "claude:sonnet" 2 40 "src/app.ts"
check_with_context "a claude:opus label selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "claude:opus" 2 40 "src/app.ts"
check_with_file_context "file-based PR metadata selects the opus profile" \
  "$OPUS" "$OPUS_T" "claude:opus" "src/app.ts"
check_rejected "conflicting model labels fail closed" \
  "" $'claude:sonnet\nclaude:opus' 2 40 "src/app.ts"
check_with_context "authentication changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 2 40 $'src/auth/callback.ts\nsrc/app.ts'
check_with_context "an authentication leaf file selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "src/auth.ts"
check_with_context "a payment leaf file selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "src/stripe.ts"
check_with_context "an MCP configuration file selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 ".mcp.json"
check_with_context "custom GitHub Actions select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 ".github/actions/release/action.yml"
check_with_context "CODEOWNERS changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 ".github/CODEOWNERS"
check_with_context "identity and OIDC changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "src/identity/oidc.ts"
check_with_context "cryptographic key changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "src/crypto/keys.ts"
check_with_context "Terraform changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "terraform/network.tf"
check_with_context "Kubernetes changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "k8s/production-rbac.yaml"
check_with_context "container compose changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "docker-compose.prod.yml"
check_with_context "non-GitHub CI changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 "Jenkinsfile"
check_with_context "environment configuration changes select the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 40 ".env.example"
check_with_context "a Superpowers spec selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 120 "docs/superpowers/specs/2026-09-26-review-routing-design.md"
check_with_context "a Superpowers plan selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 1 120 "docs/superpowers/plans/2026-09-26-review-routing.md"
check_with_context "a PR over 25 changed files selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 26 120 "src/app.ts"
check_with_context "a PR over 800 changed lines selects the opus profile" \
  "$OPUS" "$OPUS_T" "" "" 2 801 "src/app.ts"
check_with_context "an ordinary documentation PR remains on sonnet" \
  "$SONNET" "$SONNET_T" "" "" 1 120 "docs/getting-started.md"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
