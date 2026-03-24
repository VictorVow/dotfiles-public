# Daily Workflow

Common tasks for maintaining and extending this configuration.

## Adding a Package

### User package (most cases)

Edit `nix/modules/packages.nix`, add to `home.packages`:

```nix
home.packages = with pkgs; [
  # ... existing packages ...
  ripgrep   # fast grep replacement
];
```

Then apply:

```bash
hms
# or: home-manager switch --flake ~/Documents/ESSENTIALS/installs/nix#boss
```

Search nixpkgs first with `nsp <name>` (alias for `nix search nixpkgs`).

### Try a package without installing it

```bash
nsh ripgrep        # opens a shell with ripgrep available
# or:
nix shell nixpkgs#ripgrep
```

### System package (needs root)

Add to the apt list in `ansible.yml`, then:

```bash
ansible-playbook ansible.yml --ask-become-pass
```

Only use this for packages that genuinely need system-level installation (services, kernel modules, system libraries).

### Flatpak app

```bash
flatpak install flathub com.example.App
```

Run `update.sh` to keep Flatpak apps updated alongside everything else.

---

## Editing Shell Configuration

Shell aliases, PATH entries, and environment variables live in `nix/modules/shell.nix`:

- **Aliases** → `programs.bash.shellAliases`
- **PATH and other exports** → `programs.bash.initExtra`
- **Session-wide env vars** (visible to GUI apps) → `home.sessionVariables`

After editing, apply with `hms`.

---

## Editing Program Configuration

Program-specific config (git, tmux, neovim, etc.) lives in `nix/modules/programs.nix`.

### Special case: starship prompt

The starship theme is stored verbatim as `nix/dotfiles/starship.toml`. Edit that file directly and apply with `hms`. The gruvbox dark powerline theme is documented at [starship.rs](https://starship.rs/config/).

### Adding a new programs.* module

Home Manager has modules for many common tools. Check [Home Manager options](https://nix-community.github.io/home-manager/options.xhtml) for available `programs.*` and `services.*` options.

Example — adding `programs.direnv`:

```nix
# in programs.nix
programs.direnv = {
  enable = true;
  enableBashIntegration = true;
  nix-direnv.enable = true;
};
```

---

## Updating

Update all package managers in one pass:

```bash
update-all
# or: ~/Documents/ESSENTIALS/installs/update.sh
```

This runs 7 steps in sequence:
1. Nix + Home Manager (updates `flake.lock`, runs `home-manager switch`)
2. apt (system packages)
3. Homebrew (remaining brew packages)
4. npm globals (AI CLI tools in `~/.npm-global`)
5. Flatpak apps
6. pipx packages
7. Distrobox containers (apt/dnf inside `dev` and `media`)

**Skip Nix update** (use pinned flake.lock versions):

```bash
update.sh --no-nix
```

**Skip Distrobox** (faster, skip container updates):

```bash
update.sh --no-distrobox
```

**Dry run** (preview only, nothing applied):

```bash
update.sh --dry-run
```

---

## Rolling Back

Home Manager keeps a history of generations. Each `hms` or `home-manager switch` creates a new generation.

```bash
# List all generations
home-manager generations

# Roll back to a specific generation
home-manager switch --switch-generation 42

# Or roll back to the previous generation
home-manager rollback
```

If something is truly broken, the previous generation's packages are still in the Nix store and can be activated immediately.

---

## Distrobox Containers

Two containers are managed declaratively in `nix/modules/distrobox.nix`:

| Container | Base image | Purpose |
|-----------|-----------|---------|
| `dev` | ubuntu:24.04 | Build toolchains, debuggers, language runtimes |
| `media` | fedora:latest | OBS, Kdenlive, ffmpeg (RPMFusion codecs) |

```bash
# Enter a container
dbe dev          # alias for: distrobox enter dev
dbe media

# Run a command without entering
distrobox enter dev -- cmake --version

# List containers
dbl              # alias for: distrobox list

# Re-initialise a container (e.g. add new packages)
rm ~/.local/share/distrobox-hm-init/dev-initialized
hms
```

Containers are created automatically on first `home-manager switch`. The sentinel file (`~/.local/share/distrobox-hm-init/<name>-initialized`) prevents re-running the package install on every switch.

---

## Applying Changes After Editing

```bash
# Apply Home Manager changes
hms

# Verify the change took effect
which <binary>           # confirm it's in the nix profile
echo $SOME_VAR           # check env var
git config --list        # check git config
```
