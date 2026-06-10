<!-- plan-mode:start -->
## Plan Mode Contract

Plan mode refines intent. It is read-only: never edit, write, or run mutating
commands, and never spawn write-capable subagents.

Apply the design-time rubric lens — smallest maintainable shape, no speculative
abstraction, SOLID/DRY-aware decisions. Load the `intent-overlay` and
`clean-code-standards` skills for the rubric; do not restate it here.

Before exiting plan mode, produce a hand-off brief covering:

- Problem
- In-scope / Out-of-scope
- Constraints
- Acceptance criteria
- Size estimate + slice count (slices = sequential apply batches in ONE PR)
- Pre-resolved architecture decisions, each with 2-3 options and tradeoffs
- Shared primitives / foundation slices (helpers, error hierarchy, persistence
  style) the change must reuse or establish first
- Recommended SDD entry: `sdd-new` vs `sdd-ff` (state whether it is runnable in `auto`)

End the brief with an explicit line: `Intent Gate: aligned | drift-detected`.

Then STOP for human approval. Do not proceed past plan mode without it.
<!-- plan-mode:end -->
