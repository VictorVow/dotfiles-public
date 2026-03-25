# plasma-manager

> **Decision:** Potentially worth migrating to, though I want to find out more about how it manages the diff between itself + KDE settings.

[`nix-community/plasma-manager`](https://github.com/nix-community/plasma-manager) is a community Home Manager module that brings declarative management to KDE Plasma settings on any system running Home Manager — NixOS or otherwise. It translates `programs.plasma` Nix options into the INI-format `.rc` files that Plasma reads from `~/.config/`, applying them atomically at `home-manager switch` time without touching system-level state.

---

## What it manages

plasma-manager deliberately scopes itself to user-space Plasma configuration. Coverage is **incomplete** — not every KDE setting has a Nix option yet — but the major areas are:

| Category | What it controls |
|----------|-----------------|
| Workspace appearance | Color scheme, icon theme, cursor theme, wallpaper, GTK theming |
| Panels | Widget layout, panel position, size, autohide behaviour |
| Desktop | Desktop icons, widgets, mouse action assignments |
| Keyboard shortcuts | KWin global shortcuts, KRunner hotkeys, application shortcuts |
| Window rules | Per-app placement, decoration overrides, virtual desktop assignment |
| KRunner | Enabled runners, inline results, popup position |
| Screen locker | Lock timeout, appearance |
| Input devices | Touchpad speed, tap-to-click, natural scroll; mouse acceleration |
| KDE applications | Kate, Konsole, Okular, Ghostwriter, Elisa (selective; not all apps covered) |

Settings not yet covered by plasma-manager options are silently left alone — existing `~/.config/*.rc` files for those settings remain unmanaged.

### How it works

```
home-manager switch --flake ./nix#boss
```

- The `programs.plasma` options are compiled into `.rc` file writes by the Home Manager module
- Settings are applied at switch time; **a logout/login cycle is required** for Plasma to pick them up
- The `rc2nix` utility (bundled with the package) reads your existing `~/.config/*.rc` files and generates a starter Nix declaration — useful for bootstrapping from an already-configured system
- Plasma 6 is targeted on the main branch; Plasma 5 has a dedicated `plasma-5` branch

---

## What it could manage in this repo

This system runs Kubuntu with KDE Plasma 6. All Plasma settings currently live in untracked `~/.config/` files. The highest-value targets for plasma-manager:

**Appearance** — Color scheme (e.g. BreezeDark), wallpaper path, icon and cursor theme. A single `programs.plasma.workspace` block replaces hand-tweaking System Settings and ensures the same look after a reinstall.

**Global keyboard shortcuts** — KWin virtual desktop switching (`Meta+1`–`Meta+N`), window tiling shortcuts, application launch hotkeys. These are the settings most likely to be lost after a reinstall and most tedious to reconfigure manually.

**Panel layout** — Panel position, widget order, clock format, system tray pinned items. Useful on a multi-monitor setup where panel config is non-trivial.

**Konsole** — Default profile, font, color scheme, scrollback size. Konsole profile files live in `~/.local/share/konsole/` and are currently untracked.

**KRunner** — Which runners are enabled (Calculator, Apps, Files, Units, etc.), position.

**Input devices** — Touchpad or mouse tuning if defaults have been overridden in System Settings.

---

## What it cannot manage

| Area | Why |
|------|-----|
| SDDM display manager | Requires root; stays in Ansible |
| Flatpak app settings | Flatpak sandboxing; outside Plasma config entirely |
| KDE settings without Nix options | Silently left to manual management |
| Live config reload | Plasma must be restarted (logout/login) to apply changes |
| System-level KDE packages | `sddm`, `dolphin`, plasma runners — remain in Ansible |

---

## Relationship to the existing setup

plasma-manager fills **only** the user-space KDE settings gap. It does not overlap with any existing layer:

- **Ansible** continues to own: system-level KDE packages (`apt`), system services
- **Home Manager** (`nix/`) continues to own: CLI packages, dotfiles, distrobox containers
- **plasma-manager** takes over: the `~/.config/plasma*` and `~/.config/kde*` files currently edited through System Settings and untracked

It is a significantly lower-risk adoption than [`system-manager`](system-manager.md) — plasma-manager has 1,100+ stars, 67 contributors, and active maintenance, compared to system-manager's alpha status and unstable API.

---

## Integration outline

Three files need to change, plus one new module file.

### 1. `nix/flake.nix` — add the input

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  plasma-manager = {
    url = "github:nix-community/plasma-manager";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };
};
```

The `outputs` function signature needs `plasma-manager` added:

```nix
outputs = { nixpkgs, home-manager, plasma-manager, ... }: {
  homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      ./home.nix
      inputs.plasma-manager.homeManagerModules.plasma-manager
    ];
    extraSpecialArgs = { inherit inputs; };
  };
};
```

### 2. `nix/home.nix` — add the module import

```nix
imports = [
  ./modules/packages.nix
  ./modules/programs.nix
  ./modules/shell.nix
  ./modules/distrobox.nix
  ./modules/plasma.nix           # KDE Plasma settings
];
```

### 3. `nix/modules/plasma.nix` — new module

Start minimal and expand as you audit your settings:

```nix
{ ... }:

{
  programs.plasma = {
    enable = true;

    workspace = {
      colorScheme = "BreezeDark";
      # wallpaper = "/path/to/wallpaper.jpg";
      # iconTheme = "breeze-dark";
      # cursorTheme = "breeze_cursors";
    };

    # shortcuts.kwin."Switch to Desktop 1" = "Meta+1";
    # shortcuts.kwin."Switch to Desktop 2" = "Meta+2";
    # Add further settings here as you migrate them from System Settings
  };
}
```

### Bootstrapping with rc2nix

To generate a starter declaration from your current System Settings:

```bash
# Run from within a nix shell that has plasma-manager available
nix run github:nix-community/plasma-manager#rc2nix

# Or if already integrated:
rc2nix > /tmp/plasma-current.nix
```

The output needs hand-cleanup before committing — it tends to include redundant defaults and sometimes produces non-idiomatic Nix. Use it as a reference, not as a drop-in.

### Files modified

| File | Change |
|------|--------|
| `nix/flake.nix` | Add `plasma-manager` input; thread it into `homeManagerConfiguration` |
| `nix/home.nix` | Add `./modules/plasma.nix` to imports |
| `nix/modules/plasma.nix` | New file: `programs.plasma` declarations |

---

## Key caveats

- **Coverage is incomplete.** Many KDE settings still have no Nix option. Unsupported settings are silently ignored — you must continue managing them manually (or accept their current state after a reinstall).
- **Logout/login required.** plasma-manager writes the config files but Plasma only reads them at session start. Running `home-manager switch` mid-session will not apply changes until you log out.
- **Ctrl+Alt+T and Print keybindings** are known to be problematic — these specific shortcuts may not apply correctly through plasma-manager.
- **`rc2nix` output needs cleanup.** The generated Nix is a starting point, not production-ready. Review every option it emits before committing.
- **Plasma 6 only on main branch.** The nixpkgs-unstable input already tracks Plasma 6 on Kubuntu, so this aligns correctly. If you ever pin to a stable channel, verify the Plasma version.
- **Settings not in plasma-manager revert silently.** If you do a clean reinstall and apply the Home Manager config, settings without Nix declarations will revert to KDE defaults — there is no warning. Document what remains unmanaged in `docs/limitations.md`.
