# Nix Usage: Ephemeral Packages and Dev Environments

How to use Nix to try packages, run tools, and set up project-specific environments without permanently installing anything.

## Mental model

| Scope | Tool | Persists? |
|-------|------|-----------|
| Permanent, declarative | Home Manager (`packages.nix`) | Yes — survives reboot, tracked in git |
| Temporary shell | `nix shell` / `nsh` | No — gone when shell exits |
| One-shot execution | `nix run` | No — runs and exits |
| Project dev environment | `nix develop` | No — active while in shell |
| Auto-load on `cd` | direnv + `use flake` | While in directory |
| Explore package tree | `nix repl` | Session only |

---

## Finding packages

Before using any of the tools below, find the exact nixpkgs attribute name:

```bash
nsp ripgrep                    # alias for: nix search nixpkgs ripgrep
nix search nixpkgs python3     # search by keyword
```

Or browse the web UI at [search.nixos.org/packages](https://search.nixos.org/packages).

The attribute name (e.g. `ripgrep`, `python312`, `nodejs_22`) is what you pass as `nixpkgs#<name>`.

---

## nix shell — temporary package in PATH

Drops you into a subshell with one or more packages available. Nothing is installed permanently.

```bash
# Single package
nix shell nixpkgs#ripgrep
nsh nixpkgs#ripgrep            # same thing, using local alias

# Multiple packages
nix shell nixpkgs#ffmpeg nixpkgs#yt-dlp

# Run one command then exit (no interactive shell)
nix shell nixpkgs#jq --command jq --version
nix shell nixpkgs#nodePackages.typescript --command tsc --version
```

Exit with `exit` or Ctrl-D. The package disappears from PATH immediately.

**Pinning to a specific nixpkgs revision:**

```bash
nix shell github:NixOS/nixpkgs/nixos-24.11#ripgrep
```

**From a local flake** (e.g. testing a package defined in the current project):

```bash
nix shell .#mypackage
```

---

## nix run — execute without a shell

Runs the default app of a package and exits. Good for formatters, generators, and scripts you don't need a shell for.

```bash
nix run nixpkgs#cowsay -- "hello"
nix run nixpkgs#nixpkgs-fmt -- myfile.nix
nix run nixpkgs#hello
```

Arguments after `--` are passed to the program. Without `--`, anything after the flake ref is interpreted as a nix run flag.

---

## nix develop — project dev environment

Enters a shell with all build inputs, compilers, and tools defined in a flake's `devShell`. Unlike `nix shell` (which adds executables), `nix develop` sets up a full build environment: `$CC`, `$PKG_CONFIG_PATH`, library paths, etc.

Requires a `flake.nix` in the project with a `devShells` output.

### Minimal flake.nix with a devShell

```nix
{
  description = "My project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        nodejs_22
        python312
        rustup
        pkg-config
        openssl
      ];

      shellHook = ''
        echo "dev env ready"
        export DATABASE_URL="postgres://localhost/myapp_dev"
      '';
    };
  };
}
```

### Using it

```bash
# Enter default devShell (looks for flake.nix in current or parent directories)
nix develop

# Enter a named devShell
nix develop .#ci

# Run a command without entering an interactive shell
nix develop --command bash -c "npm test"
nix develop --command make build
```

Exit with `exit` or Ctrl-D.

---

## direnv — auto-load on cd

[direnv](https://direnv.net) watches `.envrc` files and automatically activates/deactivates environments as you navigate directories. Combined with `nix-direnv`, it hooks into `nix develop` so the dev environment loads the moment you enter a project directory.

### Setup

direnv is not currently in `packages.nix`. Add both direnv and nix-direnv via Home Manager:

```nix
# in nix/modules/programs.nix
programs.direnv = {
  enable = true;
  enableBashIntegration = true;
  nix-direnv.enable = true;   # caches the nix environment, much faster than plain direnv
};
```

Apply with `hms`.

### Project setup

In any project with a `flake.nix`:

```bash
# Create .envrc
echo "use flake" > .envrc

# Trust this directory
direnv allow
```

Now every `cd` into that directory automatically runs the flake's devShell. `cd` out and the environment is unloaded.

### .envrc variants

```bash
use flake                        # use default devShell from flake.nix in current dir
use flake .#ci                   # use named devShell
use flake github:NixOS/nixpkgs   # use a remote flake (rare)

# You can also set env vars alongside the flake:
use flake
export API_KEY="dev-only-key"
```

### VS Code integration

Install the [direnv VS Code extension](https://marketplace.visualstudio.com/items?itemName=mkhl.direnv). It picks up `.envrc` automatically so the integrated terminal and language servers see the same environment.

### Why nix-direnv

Without `nix-direnv`, direnv re-evaluates the flake on every shell start (slow). `nix-direnv` caches the result in the Nix store and only rebuilds when `flake.lock` changes.

---

## nix repl — explore nixpkgs interactively

Useful for finding exact attribute paths before writing Nix config.

```bash
nix repl
```

Inside the repl:

```
# Load nixpkgs (unstable, matching this repo's flake)
nix-repl> :lf github:NixOS/nixpkgs/nixpkgs-unstable

# Browse packages
nix-repl> legacyPackages.x86_64-linux.ripgrep
nix-repl> legacyPackages.x86_64-linux.python312Packages.requests

# Tab-complete to explore
nix-repl> legacyPackages.x86_64-linux.python312<TAB>

# Load the local flake
nix-repl> :lf .

# Inspect a derivation
nix-repl> legacyPackages.x86_64-linux.ripgrep.version
```

Exit with `:q` or Ctrl-D.

---

## nix-locate — find which package provides a binary

`nix-index` is already configured (`programs.nix-index` in `programs.nix`). Use it to answer "which nixpkgs package contains binary X?":

```bash
nix-locate --top-level --whole-name bin/rg    # find package providing `rg`
nix-locate bin/terraform
```

The database is built by running `nix-index` (takes a few minutes, only needed once or after major nixpkgs updates).

---

## Quick reference

| Task | Command |
|------|---------|
| Try a package now | `nsh nixpkgs#<pkg>` |
| Run a tool once | `nix run nixpkgs#<pkg> -- <args>` |
| Enter project dev env | `nix develop` (in dir with flake.nix) |
| Auto-load dev env on cd | direnv + `use flake` in `.envrc` |
| Search for a package | `nsp <keyword>` |
| Find which pkg has a binary | `nix-locate bin/<name>` |
| Explore package attributes | `nix repl` then `:lf nixpkgs-unstable` |
| Add permanently | Edit `packages.nix`, run `hms` |
