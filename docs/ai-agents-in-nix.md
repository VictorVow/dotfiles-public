# AI Agents in Nix

How AI coding agents (claude, codex, gemini-cli, cline, etc.) relate to Nix and Home Manager, and whether to adopt `llm-agents.nix`.

## Current Approach: Mixed — Nix for claude/codex/gemini-cli, npm for others

The agent landscape is split. Claude, Codex, and Gemini CLI are all in nixpkgs-unstable and have first-class Home Manager modules, so they're managed declaratively through Nix. The remaining agents (cline, continue, opencode, copilot-cli) are not yet in nixpkgs and are installed via a `home.activation` script in `nix/modules/shell.nix` that calls `npm install -g` into `~/.npm-global`. That approach is declarative in *intent* but not truly reproducible — npm installs the latest version at activation time, not a pinned one.

### Claude, Codex, Gemini CLI — `programs.*` (nixpkgs-unstable)

All three are installed from nixpkgs-unstable via Home Manager program modules (`nix/modules/programs.nix`), with versions pinned in `flake.lock`. Claude gets full config (settings, hooks, MCP, agents, slash commands); Codex gets MCP integration; Gemini CLI is enabled with no managed settings due to a [known HM bug](https://github.com/nix-community/home-manager/issues/8654) where `settings` writes a read-only Nix store symlink that blocks OAuth login.

### Other agents — Home Manager activation + npm

| Pros | Cons |
|------|------|
| Declarative listing in `shell.nix` — tools are part of the config | npm versions are floating (not pinned), breaks reproducibility |
| Single `home-manager switch` installs everything on a new machine | Requires npm as a runtime dependency alongside Nix |
| Integrated into `update.sh` workflow | Native-binary tools can't be expressed as npm packages |
| No external flake inputs or third-party trust required | nixpkgs itself has almost no AI agent packages — lags rapid release cycles |
| HM generation rollback reverts the config; the tools themselves are unaffected | npm global state lives outside the Nix store — not atomic, no Nix-level rollback of binaries |

## Claude: nixpkgs-unstable vs `llm-agents.nix`

[`llm-agents.nix`](https://github.com/numtide/llm-agents.nix) is a Nix flake by numtide (865 stars, ~6 000 commits, daily updates) that packages 70+ AI agents — including `claude-code` and 9 Claude Code ecosystem companion tools — as proper Nix derivations with a pre-built binary cache. It is **not mutually exclusive** with the `programs.claude-code` HM module: you can keep all existing module configuration (settings, hooks, MCP, agents) and simply override the package — `package = inputs.llm-agents-nix.packages.${system}.claude-code` — to get llm-agents.nix's daily build instead of nixpkgs-unstable's.

| For `llm-agents.nix` | For `nixpkgs-unstable` (current) |
|---|---|
| Daily builds of the latest claude-code release | Version pinned in `flake.lock` — fully reproducible |
| Pre-built binary cache — no local compilation | No additional flake input or trust surface |
| Update independently of nixpkgs (no full `nix flake update`) | `programs.claude-code` HM module manages settings, hooks, MCP, agents declaratively |
| 9 Claude Code ecosystem companion tools included | Atomic upgrade and rollback via HM generations |
| Can be combined with the HM module — just override `package =` | Fewer moving parts; failure modes are well-understood |
| Removes the days/weeks lag between release and nixpkgs packaging | Self-contained — no dependency on numtide staying active |
