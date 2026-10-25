import { Plugin } from "@opencode/plugin"
import { execFile } from "node:child_process"
import { promisify } from "node:util"

const run = promisify(execFile)

// RTK OpenCode plugin — rewrites commands to use rtk for token savings.
// Requires: rtk >= 0.23.0 in PATH.
//
// This is a thin delegating plugin: all rewrite logic lives in `rtk rewrite`,
// which is the single source of truth (src/discover/registry.rs).
// To add or change rewrite rules, edit the Rust registry — not this file.

export default Plugin.define({
  id: "rtk",
  async setup(ctx) {
    try {
      await run("which", ["rtk"])
    } catch {
      console.warn("[rtk] rtk binary not found in PATH — plugin disabled")
      return
    }

    await ctx.shell.hook("create.before", async (event) => {
      const command = event.command
      if (!command) return

      // `rtk rewrite` may exit non-zero (e.g. exit 3 when no global hook is
      // installed) yet still print a valid rewrite, so use stdout from either
      // the fulfilled or rejected result.
      let stdout: string | undefined
      try {
        stdout = (await run("rtk", ["rewrite", command])).stdout
      } catch (err) {
        stdout = (err as { stdout?: string }).stdout
      }

      const rewritten = stdout?.trim()
      if (rewritten && rewritten !== command) {
        event.command = rewritten
      }
    })
  },
})
