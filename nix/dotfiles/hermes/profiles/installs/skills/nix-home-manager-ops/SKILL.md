---
name: nix-home-manager-ops
description: "Run and verify Home Manager switches on these Nix hosts."
version: 0.1.0
author: Installs agent
license: MIT
compatibility: "Requires Nix Home Manager"
metadata:
  hermes:
    tags: [nix, home-manager, hms, nvd]
    related_skills: [nix-switch, config-repo-review]
---

# Nix Home Manager operations on this user's hosts

## When to Use

Use whenever running, verifying, or debugging a `home-manager switch` / `hms` on the user's Nix-managed hosts (boss-laptop desktop, lord-ubuntu server) — including post-switch package diffing with `nvd`, locating HM generations, or interpreting switch warnings.

The user's own `nix-switch` skill (repo: `~/Projects/installs/nix/dotfiles/agent-skills/nix-switch/SKILL.md`, deployed to `~/.claude/skills` as a store symlink) is the canonical procedure. This skill carries host-specific facts that the repo skill cannot absorb via `skill_manage` (its deployed symlink is read-only — edit the repo source instead), plus the generation-diff pitfall discovered on these hosts.

## Procedure (manual switch, mirroring what `hms()` does)

1. Resolve the flake target per host: `~/Projects/installs/nix#boss` (desktop) or `~/installs/nix#lord` (lord-ubuntu).
2. Always pass `--no-write-lock-file` — only `update-all` may advance `flake.lock` (age-pinned for Hydra cache). A refusal to write the lock means `flake.nix` drifted; surface it, never drop the flag.
3. Capture the CURRENT generation before switching:
   `old=$(readlink -f ~/.local/state/nix/profiles/home-manager)`
4. Run `home-manager switch --flake <target> --no-write-lock-file`.
5. Diff: `nvd diff "$old" ~/.local/state/nix/profiles/home-manager` → added/removed/up/downgraded list + closure delta. Skip the diff gracefully when `nvd` is absent or the switch failed.
6. After edits to Nix modules, lint from the repo root: `just lint-nix` (statix + deadnix, via `nix develop ./nix`).

## Pitfalls

- Never diff against `~/.nix-profile` — on these hosts it resolves to the `nix profile` **user-environment**, not the HM generation, producing a bogus diff claiming hundreds of removed paths. HM generations are the `home-manager-<N>-link` entries in `~/.local/state/nix/profiles/`, with the `home-manager` symlink tracking the current one.
- `warning: Git tree ... has uncommitted changes` from a switch is always ignorable.
- The canonical per-switch rules (commit flow, news items) live in the repo `nix-switch` skill; keep that file as the cross-agent source of truth and update it in the repo when this one and it disagree.
