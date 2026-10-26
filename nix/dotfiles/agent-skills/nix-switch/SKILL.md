---
name: nix-switch
description: Run home-manager switch and show any new news items.
compatibility: "Requires Nix Home Manager"

---
1. If the user tells you to run `hms` then instead run `home-manager switch --flake ~/Projects/installs/nix#boss --no-write-lock-file` since you don't have access to `hms` from your Bash shell.
   - The `--no-write-lock-file` flag is important: only `update.sh` (run via `update-all`) is allowed to advance `flake.lock`. The repo intentionally pins nixpkgs / home-manager to a 2-week-old upstream commit so Hydra's binary cache has caught up — without that pin, ad-hoc switches risk recompiling large packages from source. If a switch fails because it wants to write the lock, surface that to the user (it means something edited `flake.nix` since the last `update-all`); don't drop the flag to "fix" it.
2. If you see "warning: Git tree <filepath> has uncommitted changes" then just ignore that warning.
3. If it failed, show the full error and suggest a fix.
4. Don't run `home-manager news` unless it's part of the update.sh script.
5. If the switch succeeded, end the run by loading the `git-commit` skill and committing the flake changes (e.g. `flake.nix`, `flake.lock`, modules, dotfiles) produced by the switch. If the working tree is clean, say so instead of making an empty commit.
