<!-- gate-wiring:start -->
## Gate Wiring

For ANY subagent that reads, writes, or reviews code (`sdd-apply`, `sdd-verify`,
`jd-*`), always inject both gate skills as "Skills to load before work":

- From the project skill registry when present.
- Otherwise, the canonical fallback:
  - `~/.codex/skills/intent-overlay/SKILL.md`
  - `~/.codex/skills/clean-code-standards/SKILL.md`

Never skip the gate skills because the registry is missing — fall back instead.

No-SDD path: any turn that edited code MUST end with
`Clean Code Gate: passed | blocked`. On `blocked`, fix the issue or surface it
to the human — never declare the turn done.
<!-- gate-wiring:end -->
