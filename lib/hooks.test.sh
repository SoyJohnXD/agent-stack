#!/usr/bin/env bash
# Tests for hooks/check-plan-contract.sh
# Run: bash lib/hooks.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/check-plan-contract.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# run_hook <plan_text> — feeds a PreToolUse(ExitPlanMode) payload to the hook
# and prints its stdout.
run_hook() {
  local plan="$1"
  printf '%s' "$plan" | jq -Rs '{tool_input: {plan: .}}' | bash "$HOOK"
}

# ---------------------------------------------------------------------------
# T1 — negation plan: claims sections are absent/unneeded -> DENIED
# ---------------------------------------------------------------------------
NEGATION_PLAN='Intent Gate: aligned
No decisions needed for this trivial change.
There are no options to consider, this is sliced bread already.
We have eaten the acceptance test cake.'

NEG_OUT=$(run_hook "$NEGATION_PLAN")
NEG_DECISION=$(printf '%s' "$NEG_OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""')
NEG_REASON=$(printf '%s' "$NEG_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')

[ "$NEG_DECISION" = "deny" ] && pass "T1: negation plan is denied" || fail "T1: negation plan should be denied (got decision: '$NEG_DECISION')"

case "$NEG_REASON" in
  *"size estimate"*|*"slice"*) pass "T1: denial flags missing size estimate / slice count" ;;
  *) fail "T1: denial should flag missing size estimate / slice count (got: $NEG_REASON)" ;;
esac

case "$NEG_REASON" in
  *"acceptance criteria"*) pass "T1: denial flags missing acceptance criteria" ;;
  *) fail "T1: denial should flag missing acceptance criteria (got: $NEG_REASON)" ;;
esac

# ---------------------------------------------------------------------------
# T2 — compliant plan: all required sections present -> silent pass (exit 0,
# no stdout)
# ---------------------------------------------------------------------------
COMPLIANT_PLAN='Intent Gate: aligned
Size estimate: 3 slices.
Decision: use approach A over option B for simplicity.
Acceptance criteria: tests pass and lint is clean.'

COMPLIANT_OUT=$(run_hook "$COMPLIANT_PLAN")
COMPLIANT_EXIT=$?

[ "$COMPLIANT_EXIT" -eq 0 ] && pass "T2: compliant plan exits 0" || fail "T2: compliant plan should exit 0 (got: $COMPLIANT_EXIT)"
[ -z "$COMPLIANT_OUT" ] && pass "T2: compliant plan produces no deny output" || fail "T2: compliant plan should produce no output (got: $COMPLIANT_OUT)"

# ---------------------------------------------------------------------------
# T3 — plan with 'decision' but no 'option' -> DENIED for missing
# decisions-with-options section
# ---------------------------------------------------------------------------
NO_OPTION_PLAN='Intent Gate: aligned
Size estimate: 2 slices.
We made a decision about the approach.
Acceptance criteria: tests pass.'

NO_OPTION_REASON=$(run_hook "$NO_OPTION_PLAN" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
case "$NO_OPTION_REASON" in
  *"decisions with options"*) pass "T3: plan with 'decision' but no 'option' is denied for missing decisions-with-options" ;;
  *) fail "T3: should be denied for missing decisions-with-options (got: $NO_OPTION_REASON)" ;;
esac

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
