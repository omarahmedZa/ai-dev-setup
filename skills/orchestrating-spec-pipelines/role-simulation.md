# Role-Based Decision Fallback

Triggered when a phase subagent returns `BLOCKED` with reason containing: "design choice", "ambiguous", "tradeoff", "which approach", "unclear whether", or "could go either way".

## Protocol

### 1. Dispatch 4 Parallel Subagents

Each receives:
- The phase plan file path (for context)
- The exact blocker text verbatim from the implementer's report
- A one-paragraph **role lens** (below)
- Instruction: "You are role-playing. Return exactly one verdict: your recommended approach and a 1-2 sentence justification. Do not discuss other roles, do not negotiate."

### 2. Role Lenses

**CEO** — prioritizes business value, time-to-market, strategic coherence, user adoption. Question: "What serves the product and business best?"

**Designer** — prioritizes user experience, consistency, simplicity, accessibility. Question: "What would the user want and understand?"

**Engineer** — prioritizes feasibility, maintainability, technical debt, performance. Question: "What can we build well and maintain?"

**Security** — prioritizes data safety, least privilege, attack surface, compliance. Question: "What keeps the system and users safe?"

### 3. Synthesize Verdicts

| Split | Rule |
|-------|------|
| 4-0 or 3-1 | Apply majority choice |
| 2-2 | Break tie: Engineer vote + CEO override (Engineer knows buildability, CEO owns product) |

### 4. Record and Continue

Write verdict to state file's `Blocker` field as resolved, re-dispatch the phase subagent with the resolved choice as additional context in the dispatch prompt.

## Fast-Path Skip

If the blocker contains a clearly obvious answer (the implementer flagged it but there's only one reasonable path given the spec), answer inline and skip role simulation. This saves 4 subagent dispatches for trivial decisions.

## Anti-Patterns

- Don't use role simulation for technical blockers (missing dependency, test failure)
- Don't use it preemptively — only when the implementer reports BLOCKED
- Don't let role discussion loop — synthesize once, decide, move on
