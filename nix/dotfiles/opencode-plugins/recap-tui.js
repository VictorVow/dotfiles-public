// Recap TUI plugin for OpenCode v2 (`opencode2`) — a port of Claude Code's
// /recap: "generate a one-line summary of the current session on demand".
//
// Deployed as a directory plugin (~/.config/opencode/plugins/recap/): v2 only
// loads a TUI entry from a directory's `tui.js`, and the directory also needs
// a server entry (`index.js`, re-exporting this; setup no-ops there since the
// server ctx has no `ui`/`keymap`). Same deployment shape as turn-verbosity.
//
// There is no recap endpoint: the command asks the session's own model for a
// one-liner via `session.prompt`, then shows it as a toast — same end state
// as Claude Code's "one line, ready when you return". The prompt carries
// `system` so the model knows this is a side query, and `noReply` is NOT set
// because we need the text back.
//
// The exchange is visible in the transcript (the recap request + its reply
// appear as a normal turn) — unlike Claude Code's out-of-band recap, v2 gives
// a plugin no way to inject hidden context. The prompt asks for a single
// line, so the pollution is bounded.
// shortcut: recap runs on the session's primary model (whatever the prompt
// box has selected) rather than a cheap small_model — upgrade if upstream
// exposes the title/summary model to the prompt call or adds a native recap
// endpoint.
// CLI TUI only: Orca's native chat doesn't load cli.json plugins.

const TITLE = "Recap";
const PROMPT =
  "Summarize this session so far in one short line for a recap. " +
  "Cover what was done and where things stand right now. " +
  "Answer with the summary line only: no preamble, no quotes, no markdown.";

function isTui(ctx) {
  return typeof ctx?.keymap?.layer === "function" && typeof ctx?.ui?.toast?.show === "function";
}

export default {
  id: "recap",
  setup(ctx) {
    if (!isTui(ctx)) return async () => {};

    const toast = (message, variant = "info") =>
      ctx.ui.toast.show({ title: TITLE, message, variant, duration: 8000 });

    const sessionID = () => {
      const route = ctx.ui?.router?.current?.();
      return route?.type === "session" ? route.sessionID : undefined;
    };

    async function recap() {
      const id = sessionID();
      if (!id) {
        toast("No session open", "warning");
        return;
      }
      const session = ctx.data?.session;
      if (typeof session?.status === "function" && session.status(id) === "running") {
        toast("Session is busy — wait for the current turn to finish", "warning");
        return;
      }
      // Recapping a fresh session wastes a model call on nothing.
      const messages = typeof session?.message?.list === "function" ? session.message.list(id) : [];
      if (!messages?.length) {
        toast("Nothing to recap yet", "warning");
        return;
      }
      const model = ctx.ui?.model?.current?.();
      toast("Summarizing…");
      try {
        const res = await ctx.client.session.prompt({
          path: { sessionID: id },
          body: {
            ...(model?.providerID && model?.modelID
              ? { model: { providerID: model.providerID, modelID: model.modelID } }
              : {}),
            system:
              "The user asked for a session recap (/recap). This is a side query, " +
              "not a new task: do not start work, do not call tools, just answer.",
            parts: [{ type: "text", text: PROMPT }],
          },
        });
        if (res?.error) throw new Error(res.error.message ?? JSON.stringify(res.error));
        const text = (res?.data?.parts ?? [])
          .filter((p) => p?.type === "text" && typeof p.text === "string")
          .map((p) => p.text)
          .join("\n")
          .trim();
        toast(text || "The model returned no summary", text ? "success" : "warning");
      } catch (err) {
        toast(`Failed: ${err?.message ?? err}`, "error");
      }
    }

    ctx.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "session.recap",
          title: "Recap session",
          group: "Session",
          palette: true,
          slash: { name: "recap" },
          run: () => void recap(),
        },
      ],
    }));

    return async () => {};
  },
};
