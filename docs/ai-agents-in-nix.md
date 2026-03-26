# AI Agents in Nix

How AI coding agents (claude, codex, cline, etc.) relate to Nix and Home Manager, and whether to adopt `llm-agents.nix`.

## Current Approach: Home Manager + npm

nixpkgs has almost no coverage of AI coding agents — these tools release fast, often ship as Node.js CLIs or native binaries, and take time to reach the stable package set. The current workaround is a `home.activation` script in `nix/modules/shell.nix` that calls `npm install -g` for each tool into `~/.npm-global`. This is declarative in *intent* — the list lives in the config — but not truly reproducible because npm installs the latest version at the time of activation, not a pinned one.

| Pros | Cons |
|------|------|
| Declarative listing in `shell.nix` — tools are part of the config | npm versions are floating (not pinned), breaks reproducibility |
| Single `home-manager switch` installs everything on a new machine | Requires npm as a runtime dependency alongside Nix |
| Integrated into `update.sh` workflow | Native-binary tools (e.g. claude's native installer) can't be expressed as npm packages |
| No external flake inputs or third-party trust required | nixpkgs itself has almost no AI agent packages — lags rapid release cycles |
| HM generation rollback reverts the config; the tools themselves are unaffected | npm global state lives outside the Nix store — not atomic, no Nix-level rollback of binaries |

## `llm-agents.nix` vs Nix/Home Manager

[`llm-agents.nix`](https://github.com/numtide/llm-agents.nix) is a Nix flake maintained by numtide (865 stars, ~6 000 commits, daily updates) that packages 70+ AI coding agents as proper Nix derivations — including claude-code, codex, gemini-cli, copilot-cli, and a dedicated Claude Code ecosystem category. Packages are pre-built and served from numtide's binary cache, so there's no local compilation. It can be added as a flake input and consumed via an overlay or `nix run` for one-off use.

| For `llm-agents.nix` | For `Nix`/`Home Manager` |
|----------------------|--------------------------|
| All 70+ tools are proper Nix packages — pinned, atomic, rollback-able | No additional flake input — keeps `flake.nix` lean |
| Pre-built binary cache means no local compilation overhead | No external trust surface (numtide cache + signing keys) |
| Updates are daily and coordinated across all tools | Current npm approach already works and is declarative |
| Native binaries packaged directly — supports tools that aren't on npm | Fewer moving parts; failure modes are well-understood |
| `nix run` for ad-hoc use without permanent install | nixpkgs AI coverage may improve over time, reducing the gap |
| Claude Code + 9 companion ecosystem tools in one flake | Self-contained — no dependency on a third-party org staying active |
