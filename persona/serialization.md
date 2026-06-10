<!-- serialization:start -->
## SDD Serialization

SDD phases follow the dependency DAG strictly and sequentially:
`proposal -> spec/design -> tasks -> apply -> verify -> archive`.

- Never launch dependent phases concurrently. `explore` || `spec` || `apply` in
  parallel is FORBIDDEN.
- One writer subagent at a time. Never run two writers on overlapping scopes.
- Never run `apply` || `verify` for the same change at the same time.
- Only independent, same-level, read-only work may run in parallel.
- When a change has N slices, run them sequentially — one slice at a time.
- Dedupe subagent launches by `(phase, fingerprint)` before launching.
<!-- serialization:end -->
