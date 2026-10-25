# Pipeline State File Schema

**Location:** `<project-root>/.superpowers/pipeline/state.md`

One file owned by the orchestrator. SDD workspaces live independently at `.superpowers/sdd/<phase-plan-name>/`.

## Format

```markdown
# Pipeline State — Spec: <spec-file-path>
# Created: <ISO timestamp>
# Mode: greenfield | brownfield

## Phase <N>: <Name>
- Status: pending | in_progress | complete | blocked
- Plan: <phase-plan-file-path>
- Commits: <base7>..<head7>  (only when complete)
- Model: <model-used>  (only when started)
- Started: <ISO timestamp>  (only when started)
- Depends: Phase <X>, Phase <Y>  (optional, omit if no deps)
- Ledger: <sdd-workspace-path>/progress.md  (only when in_progress or complete)
- Blocker: <reason>  (only when blocked)

## Phase <M>: <Next Name>
...
```

## Rules

- **One line per field** — grep/sed parseable from any session
- **`Depends`** — comma-separated phase numbers. Determines dispatch eligibility
- **`Ledger`** — pointer to SDD's own progress.md, never duplicated content
- **`Model`** — recorded for cost tracking and fix-loop escalation decisions
- **Status transitions**: `pending → in_progress → complete` or `pending → in_progress → blocked → in_progress → complete`
- **Recovery**: on session restart, `cat state.md` to find first non-complete phase and resume

## Parallel Dispatch Eligibility

Phases are eligible for parallel dispatch when:
1. All their `Depends` are `complete`
2. They touch disjoint file sets (no overlapping `Modify:` or `Create:` entries in their plan files)
3. At least one other phase also meets criteria 1 and 2

Otherwise, dispatch sequentially in dependency order.
