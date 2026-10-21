---
name: direnv-deploy
description: Set up (or upgrade) nix-direnv in this repo, optionally kept out of git via .git/info/exclude. Repos under ~/Projects/Git/1MY_REPOS/Self-Hosted share the central 1-COMMON flake instead of getting their own .nix dir.
argument-hint: "[ignore|exclude|plain]"
---
**Skill version: 3** — bump this whenever the setup steps below change significantly (anything that changes the files written or the exclude entries). The version is stamped into the deployed `.envrc` so a later run can tell an old setup from a current one.

## Repo families

Before anything else, work out which family the repo belongs to:

- **Self-Hosted** — the repo's top level is an immediate (or near, e.g. `News/News-deploy`) subdirectory of `~/Projects/Git/1MY_REPOS/Self-Hosted`. These repos do NOT get their own `.nix/flake.nix`; they load the shared deploy toolchain (Ansible, just, yamllint, gcloud, …) from the sibling `1-COMMON` flake. Follow *Self-Hosted setup* below.
- **Standalone** — anything else (this installs repo, other projects). Follow *Standalone setup* below.

If a Self-Hosted repo genuinely needs extra tools that 1-COMMON doesn't provide (check `~/Projects/Git/1MY_REPOS/Self-Hosted/1-COMMON/flake.nix` first — it may already have them), keep the repo's own `flake.nix` for just those extras and load BOTH flakes, own first then 1-COMMON last so it wins on overlap (see `logseq-sync/.envrc` for the pattern). Mention this to the user when doing it.

## Mode

Argument: `$ARGUMENTS`

- `ignore` or `exclude` → **exclude** mode: the direnv files are listed in `.git/info/exclude` so they never show up in git.
- `plain` → **plain** mode: nothing is added to `.git/info/exclude`; the files are left visible to git so they can be committed.
- No argument → ask with the AskUserQuestion tool whether to exclude the direnv files from git (options: "Exclude from git" / "Plain (commit-able)"). If an existing setup is detected (below), put its current mode first and mark it "(Recommended)"; otherwise put "Exclude from git" first as the recommended option.

## Detect an existing setup

Before writing anything, check the repo's top level:

- **No `.envrc`** → fresh install, go to the family's *Setup*.
- **`.envrc` first line is `# direnv-deploy v<N> (<mode>)`**:
  - `N` equals the current skill version and the mode matches → tell the user it's already up to date; only re-run `direnv allow` if direnv reports it as blocked. Stop.
  - `N` is lower, or the mode differs → upgrade: re-apply *Setup* with the current instructions, keeping the existing `.nix/flake.nix` packages (edit it rather than regenerating it from scratch). Then tell the user which version/mode it moved from and to.
- **`.envrc` exists without that marker** → a pre-versioning setup or a hand-written one:
  - **Self-Hosted repo**: if it contains `use flake ../1-COMMON` (the standard hand-written pattern), it IS the current Self-Hosted setup — add only the `direnv-deploy` marker line on top (mode: plain, since these `.envrc`s are committed) and, if it lacks them, the `watch_file` lines. If `.nix/` also exists in that repo, ask the user whether it can be removed in favour of 1-COMMON.
  - **Standalone repo**: if it contains `use flake "path:$PWD/.nix"` and `.nix/flake.nix` exists, it's a v1/v2 deploy: its mode is exclude if `.nix/` is in `.git/info/exclude`, else plain. Upgrade it as above.
  - Anything else (different `use …` lines, extra env setup, or `.envrc` tracked by git per `git ls-files --error-unmatch .envrc`) → don't overwrite. Show the user its contents and ask with AskUserQuestion whether to replace it, merge the current setup into it (keep their extra lines below the managed ones), or stop.

## Self-Hosted setup

For repos under `~/Projects/Git/1MY_REPOS/Self-Hosted`:

1. Write `.envrc` in the repo's top level with exactly:
   ```
   # direnv-deploy v3 (<mode>)
   # Shared deploy toolchain (Ansible, just, …) lives in 1-COMMON's flake.
   watch_file ../1-COMMON/flake.nix ../1-COMMON/flake.lock
   use flake ../1-COMMON
   ```
   If the repo sits one level deeper (e.g. `News/News-deploy`), adjust the relative path (`../../1-COMMON`). When the repo also has its own `flake.nix` for extras, put `use flake` for it BETWEEN the marker line and the watch_file pair (see `logseq-sync/.envrc`).
2. No `.nix/` dir is created — the shared flake already exists. If the repo has a leftover `.nix/` that 1-COMMON now covers, ask before removing it.
3. Git exclude entries as in step 2 of *Standalone setup* below, except `.nix/` only applies if that dir actually exists. Note most Self-Hosted `.envrc`s are committed (plain mode) — check `git ls-files --error-unmatch .envrc` before choosing.
4. Run `direnv allow` to activate; report any evaluation errors.

## Standalone setup

1. Write `.envrc` in the top level of the repo with exactly:
   ```
   # direnv-deploy v3 (<mode>)
   use flake "path:$PWD/.nix"
   ```
   (`<mode>` is `exclude` or `plain`; when merging into a user's existing `.envrc`, these two lines go first.)
2. Git exclude entries (`.git/info/exclude`; in a worktree use `git rev-parse --git-common-dir` to find it):
   - **exclude** mode: make sure both `.envrc` and `.nix/` are present, one per line, without adding duplicates.
   - **plain** mode: remove `.envrc` and `.nix/` lines if a previous exclude-mode deploy added them.
   - If switching to exclude mode and either path is already tracked by git, warn the user that the exclude has no effect on tracked files and ask before running `git rm --cached` on them.
3. Create (or update, on upgrade) `.nix/flake.nix` with a `devShells.default` containing the packages this project needs (look at the repo's language/tooling files to decide).
4. Run `direnv allow` to activate nix-direnv and build the environment; report any evaluation errors.
