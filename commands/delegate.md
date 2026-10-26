---
description: Delegate a task to a separate implementer, review its diff, and land it
---

Use the `opencode-delegate` skill to handle this task:

$ARGUMENTS

Before dispatching:
- If the first word is a lane name, use that lane and treat the rest as the
  task. Lanes: bug-fixes, tests, implementation, complex,
  research-prototyping. Otherwise choose the lane per AGENTS.md.
- Turn the request into a delegation brief with `<task>`, `<verification_loop>`,
  `<action_safety>`, and `<structured_output_contract>`. Include the repo's
  real gate commands.
- Show me the brief plus the lane and model, and wait for my approval before
  dispatching.

After approval:
- Dispatch through `~/.agents/skills/opencode-delegate/scripts/relay.mjs` with
  `--lane <name>` in a fresh session (never `--resume-last`).
- Wait for the run, review the diff, and re-run the gates yourself.
- Commit only verified work. Never let the implementer commit.
