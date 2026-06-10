<!-- gate-wiring:start -->
## Gate Wiring

For ANY subagent that reads, writes, or reviews code (`sdd-apply`, `sdd-verify`,
`jd-*`), always inject both gate skills as "Skills to load before work":

- From the project skill registry when present.
- Otherwise, the canonical fallback:
  - `~/.codex/skills/intent-overlay/SKILL.md`
  - `~/.codex/skills/clean-code-standards/SKILL.md`

Never skip the gate skills because the registry is missing — fall back instead.

### System Gate

In `sdd-verify`, after the per-file Clean Code Gate, score the WHOLE change per
clean-code-standards `references/system-review.md` (file-list union and
change-base resolution defined there). Emit `System Gate: passed | blocked`;
`blocked` ⇒ verify FAIL.

At apply milestones (a tasks Phase completes), run the same lens over that
layer before the next Phase starts.

### Primitives forwarding

The orchestrator passes the design `## Primitives` registry (and the
`sdd/{change}/primitives` journal topic) to EVERY apply/verify subagent. Apply
subagents grep before creating any helper/error/mapper/type and record new
primitives in the journal.

No-SDD path: any turn that edited code MUST end with
`Clean Code Gate: passed | blocked`. On `blocked`, fix the issue or surface it
to the human — never declare the turn done. Substantial multi-file no-SDD work
also self-checks the System Gate before declaring done.
<!-- gate-wiring:end -->
