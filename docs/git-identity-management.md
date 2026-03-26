# Git Identity Management

Two identities are in use:

| Handle    | Email                                          | GPG Key            | Purpose       |
|-----------|------------------------------------------------|--------------------|---------------|
| Victor239 | `12621257+Victor239@users.noreply.github.com`  | `GPGKEY1` | Pseudonymous  |
| USER2    | `22418751+USER2@users.noreply.github.com`     | `GPGKEY2` | Personal      |

Victor239 is the global default. USER2 is applied selectively.

---

## Current mechanisms

### 1. Global default (`programs.nix`)

`programs.git.settings.user.*` in `nix/modules/programs.nix` sets Victor239 as the baseline for all repos. Every other mechanism overrides this.

### 2. `git su [1|2]` alias

A shell alias defined in `programs.nix` that writes identity values into the **local** `.git/config` for whichever repo you're currently in:

```
git su       # show current identity
git su 1     # set Victor239 locally
git su 2     # set USER2 locally
```

These local overrides survive `home-manager switch` and persist until manually cleared or the repo is re-cloned.

### 3. `git includeIf` (directory-scoped, automatic)

Configured in `programs.nix` via `programs.git.includes`. Git automatically merges `~/.config/git/identity-USER2` for any repo whose `.git` directory lives under `~/Documents/ESSENTIALS/installs/`:

```nix
programs.git.includes = [
  {
    condition = "gitdir:~/Documents/ESSENTIALS/installs/";
    path      = "~/.config/git/identity-USER2";
  }
];
```

No manual action required — just `cd` in and run any git command. Works in all tools (CLI, VS Code terminal, GUI clients). Add more `{ condition, path }` entries for additional directories.

To add another directory mapping, add an entry pointing to the same file (or a different identity file):

```nix
{ condition = "gitdir:~/work/client-acme/"; path = "~/.config/git/identity-USER2"; }
```

### 4. VS Code extension

`onlyutkarsh.git-config-user-profiles` (configured in `programs.nix` under `gitConfigUser.*`) stores profiles and remembers which profile was last selected per workspace. The `gitConfigUser.workspaceProfileSelections` map currently points `~/Documents/ESSENTIALS/installs` at USER2.

This is UI-driven and independent of the terminal — it writes local git config when you switch profiles from the status bar.

---

## Notable alternatives (not implemented)

### direnv

Since direnv is already used in this repo for dev environments, identity switching could piggyback on `.envrc`:

```bash
# .envrc
export GIT_AUTHOR_NAME="USER2"
export GIT_AUTHOR_EMAIL="22418751+USER2@users.noreply.github.com"
export GIT_COMMITTER_NAME="USER2"
export GIT_COMMITTER_EMAIL="22418751+USER2@users.noreply.github.com"
```

Limitations:
- Requires `direnv allow` per directory
- `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars do not set `user.signingkey`, so GPG signing still uses the global key
- Only active in shells where direnv is hooked; won't affect VS Code's built-in git or GUI clients

### Shell `cd` hook

Override the shell's directory-change event (`chpwd` in zsh, `PROMPT_COMMAND` in bash) to detect a target path and run `git config` commands:

```bash
# zsh example
chpwd() {
  case "$PWD" in
    "$HOME/Documents/ESSENTIALS/installs"*)
      git config user.name USER2 2>/dev/null ;;
  esac
}
```

Limitations:
- Fragile — only fires in interactive shell sessions
- Writes local `.git/config` entries (same as `git su`), so it mutates repo state
- Doesn't apply retroactively to already-open terminals or non-shell tools
