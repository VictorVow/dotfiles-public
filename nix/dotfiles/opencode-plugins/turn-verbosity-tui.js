// Turn-verbosity TUI plugin for OpenCode v2 (`opencode2`).
//
// Deployed as a directory plugin (~/.config/opencode/plugins/turn-verbosity/):
// v2 only loads a TUI entry from a directory's `tui.js`, and the directory
// also needs a server entry (`index.js`, re-exporting this; setup no-ops
// there since the server ctx has no `data`/`keymap`).
//
// Approximates Orca's chat layout (everything live during a turn, collapsed
// afterwards): while the routed session runs, transcript verbosity is "high";
// when it goes idle, back to "low" (tools/thoughts fold into summary rows).
//
// v2 has no transcript slot and doesn't expose group expansion to plugins, so
// the only lever is the built-in `session.verbosity.cycle` command (low →
// medium → high). Its palette title ("Verbosity: High") is the only in-memory
// read of the current level.
// shortcut: verbosity is global (older turns expand during a run) and text
// between tool runs stays visible in "low"; upgrade if upstream adds a
// per-turn collapse mode or a transcript slot.
// CLI TUI only: Orca's native chat doesn't load cli.json plugins.

const CYCLE = "session.verbosity.cycle";
const BUSY = "high";
const IDLE = "low";

export default {
  id: "turn-verbosity",
  setup(ctx) {
    const session = ctx.data?.session;
    if (typeof session?.status !== "function" || typeof ctx.data?.listen !== "function"
      || typeof ctx.keymap?.dispatch !== "function" || typeof ctx.keymap?.commands !== "function") {
      return async () => {};
    }

    const current = () => {
      const cmd = ctx.keymap.commands().find((c) => (c.name ?? c.id) === CYCLE);
      return /Verbosity:\s*(\w+)/.exec(cmd?.title ?? "")?.[1]?.toLowerCase();
    };
    const busy = () => {
      const route = ctx.ui.router.current();
      if (route?.type !== "session") return undefined;
      const root = session.root?.(route.sessionID) ?? route.sessionID;
      const family = [root, ...(session.family?.(root) ?? [])];
      return family.some((id) => session.status(id) === "running");
    };

    let disposed = false;
    let syncing = false;
    let again = false;
    // Each cycle persists to cli.json before the title updates, so step one
    // level at a time and wait for the change before the next step.
    async function sync() {
      if (syncing) { again = true; return; }
      syncing = true;
      try {
        do {
          again = false;
          const b = busy();
          if (b === undefined) break;
          const want = b ? BUSY : IDLE;
          for (let step = 0; step < 3 && !disposed; step++) {
            const before = current();
            if (!before || before === want) break;
            ctx.keymap.dispatch(CYCLE);
            for (let t = 0; t < 40 && current() === before; t++) await new Promise((r) => setTimeout(r, 25));
          }
        } while (again && !disposed);
      } finally {
        syncing = false;
      }
    }

    const unlisten = ctx.data.listen(() => { void sync(); });
    void sync();
    return async () => {
      disposed = true;
      if (typeof unlisten === "function") unlisten();
    };
  },
};
