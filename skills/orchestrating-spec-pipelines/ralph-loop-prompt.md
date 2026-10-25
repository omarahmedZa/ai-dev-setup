# Ralph Loop — Phase Dispatch Template

Template for dispatching a phase to a task subagent.

## Dispatch Prompt

```
Execute Phase <N> of the pipeline: <phase-name>

REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development

Your task: implement the phase plan at <phase-plan-file-path>. Read that file first — it contains your requirements, test cases, and step-by-step instructions with exact values.

Interfaces from completed phases:
- <list function signatures, types, and file paths produced by prior phases that this phase depends on>

Global constraints from spec:
- <verbatim from spec's global constraints section>

Resolved design decisions:
- <any role simulation verdicts or human decisions that affect this phase>

Your SDD workspace is: .superpowers/sdd/<phase-plan-basename>/
Write your report to: .superpowers/sdd/<phase-plan-basename>/<task-N>-report.md

Return status: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
If BLOCKED with a design ambiguity, clearly state the tradeoff and the options.
```
