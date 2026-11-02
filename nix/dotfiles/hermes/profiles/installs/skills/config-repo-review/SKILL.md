---
name: config-repo-review
description: Examine ~/Projects/installs, audit and change system config.
version: 1.1.0
author: installs
license: MIT
metadata:
  hermes:
    tags: [nix, home-manager, ansible, flatpak, config-audit]
    related_skills: [codebase-inspection]
---

# System-config repo review

## When to Use

- The user asks to "take a look at" / "examine" / "read" `~/Projects/installs`.
- The user asks what software they use, or for suggestions/improvements to their system config.
- Installing/adding packages or changing config in this repo (or any repo of this shape).
- Auditing any personal declarative-config repo of this shape (Nix/HM + Ansible + Flatpak + declarative lists).

The user periodically asks for a read-through of `~/Projects/installs` (Kubuntu config: Nix/Home Manager user-space, Ansible system-level, Flatpak, plus declarative lists) and expects a profile of what they run + concrete suggestions. The repo's own AGENTS.md/README are the map — do not restate them in the reply.

## Procedure

1. `git -C ~/Projects/installs status -sb && git log --oneline -5 && git diff` — ALWAYS first. Uncommitted drift is prime material (verify-before-commit suggestions); check for stale `result` symlinks and dangling GC roots.
2. Read in order, batching independent reads: `README.md` (repo map, layer rationale), `AGENTS.md` (rules: use `rg` to find config; never edit `> Decision`/`> Summary` blocks; self-hosted services live in a separate repo on lord-ubuntu, NOT here), `docs/system/architecture.md`, then the declarative package lists: `flatpak.md`, `Brewfile`, `uv-tools.txt`, `npm-globals.txt`, `appman-appimages.txt`, then `nix/modules/packages.nix` (read fully — every entry carries a *why* comment, often including why something was REMOVED), then `docs/PRIORITY.md` (the user's reading queue) and CHANGELOG head (recent workflow changes).
3. Synthesize: who this user is (tool categories, values visible in comments: minimalism, privacy, declarative-everything, documented removals) + suggestions.

## Making changes (install a package / edit a module)

1. Find the right layer with `rg` (per AGENTS.md): user package → `nix/modules/packages.nix` (or the matching `nix/modules/*.nix`); system/daemon → `ansible.yml`; 3rd-party installer → `ansible/installers/` via `custom-installers.yml`; Flatpak → `flatpak.md`; AppImage → `appman-appimages.txt`; uv/npm CLI → `uv-tools.txt` / `npm-globals.txt`. Read the surrounding comments first — a package may be deliberately absent with a removal note saying why.
2. Add the entry WITH a *why* comment in house style (every entry carries one; removals too).
3. Apply: `home-manager switch --flake ./nix#boss --no-write-lock-file` from the repo root — real execution, not a description. Verify with the tool's own output (`which <bin>`, `<bin> --version`).
4. Lint before offering a commit: `just lint` (or `nix develop ./nix --command sh -c 'statix check -c nix/statix.toml nix && deadnix --fail nix'`).
5. Leave the commit to the user unless they ask — flag what's now uncommitted, including pre-existing drift their switch just activated.

## Verifying what a switch changed (nvd)

- HM generations live at `~/.local/state/nix/profiles/home-manager-<N>-link`; the `home-manager` symlink there tracks the current one. `nvd diff <old-link> <new-link>` shows added/removed/up/downgraded packages + closure delta.
- `hms()` in `shell.nix` already runs this diff automatically post-switch (captures the pre-switch gen via `readlink -f` of that symlink).

## Suggestion categories that land well

- **Uncommitted/unverified changes** — flag `git diff` hunks that were never switched/linted; offer to run `hms` / `just lint` / verification.
- **Cross-manager duplication** — the same app claimed by two managers (e.g. a launcher in both `flatpak.md` and `appman-appimages.txt`); the user documents removals meticulously and dislikes redundant layers.
- **Stale artifacts** — dead `result` symlinks, overlapping app clusters in the ~155-entry flatpak list, config-losing duplicates of Nix-managed apps (e.g. a Flatpak Neovim that ignores programs.neovim settings).
- **PRIORITY.md queue items** — offer to research/draft one into `docs/research/` in house style (weighted comparison tables live in `docs/comparison-tables/`).

## Pitfalls

- NEVER edit `CHANGELOG.md` or `CVLOG.md` directly, not even to record work just completed — the `/system-update-changelog` and `/system-update-cvlog` skills own them and write entries on a daily timer, in arrears (tomorrow's run covers today's work). Record work in commits and let the timer describe it; a direct edit gets reverted.
- `~/.hermes` is a symlink INTO this repo: the live Hermes profile homes tree sits at `nix/dotfiles/hermes/home/` (whole tree gitignored — it holds `auth.json`, `.env`, `state.db`; only the `docs/` sibling is tracked). It is a relocated dotfiles dir, NOT a `home.file`-managed one — no Nix module writes into it. Map of Hermes memory/skill paths: `nix/dotfiles/hermes/docs/ai-hermes.md`.
- Read `packages.nix` fully before suggesting a package — most obvious tools are either already installed, removed-with-a-reason (the comment says why), or deliberately left to apt/Ansible. Removal notes are as canonical as additions.
- Self-hosted services are out of scope here: their config lives in `~/Projects/Git/1MY_REPOS/Self-Hosted` on lord-ubuntu. Only client-side pieces belong in this repo.
- Don't dump the repo map back at the user; they wrote it. Give the inferred profile + actionable deltas, and offer to execute the top one.
- `readlink -f ~/.nix-profile` here resolves to the `nix profile` **user-environment**, NOT the HM generation — diffing it against a generation reports bogus mass removals/GB deltas. Always grab HM generations via `~/.local/state/nix/profiles/home-manager*` links, never `~/.nix-profile`.
- `/nix/var/nix/profiles/per-user/<user>` doesn't exist on this setup (non-root Nix state) — profile state is under `~/.local/state/nix/profiles/`.
