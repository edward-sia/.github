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
  local desc=$1 want_model=$2 want_timeout=$3 text=$4
  local out; out=$(mktemp)
  if ! TRIGGER_TEXT="$text" GITHUB_OUTPUT="$out" bash --noprofile --norc -eo pipefail -c "$script" >/dev/null 2>"$out.err"; then
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
