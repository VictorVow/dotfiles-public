# plasma-manager migration plan

Stepwise plan for integrating [`plasma-manager`](plasma-manager.md) into the existing Home Manager setup. The goal is to move KDE Plasma settings from untracked `~/.config/` files into version-controlled Nix declarations — incrementally, with a safe rollback path at every stage.

---

## Before you start

**Pre-conditions:**
- Home Manager is working (`hms` alias runs without errors)
- Git working tree is clean (`git status` shows no uncommitted changes)
- You are logged into a full KDE Plasma 6 session (not a TTY) so settings are visible in System Settings

**Snapshot your current Plasma config:**

```bash
# Capture current state before touching anything
tar -czf ~/plasma-config-backup-$(date +%Y%m%d).tar.gz \
  ~/.config/plasma* \
  ~/.config/kde* \
  ~/.config/kwin* \
  ~/.config/kglobal* \
  ~/.config/krunnerrc \
  ~/.config/kshortsrc \
  ~/.config/khotkeysrc \
  ~/.local/share/konsole/
```

Keep this archive until the migration is fully committed and verified. If anything goes wrong you can restore it with `tar -xzf ~/plasma-config-backup-*.tar.gz -C /`.

---

## Phase 1 — Wire up the infrastructure

The goal here is to add plasma-manager to the flake and confirm it builds cleanly, before writing any actual Plasma settings.

### Step 1.1 — Add the input to `nix/flake.nix`

Edit `nix/flake.nix`. The full file after the change:

```nix
{
  description = "Home Manager configuration for boss's Kubuntu system";

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

  outputs = { nixpkgs, home-manager, plasma-manager, ... }@inputs: {
    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [
        ./home.nix
        inputs.plasma-manager.homeManagerModules.plasma-manager
      ];

      extraSpecialArgs = { inherit inputs; };
    };
  };
}
```

Key changes from the original:
- `plasma-manager` input added with pinned `nixpkgs` and `home-manager` follows
- `outputs` destructuring gets `...@inputs` so `inputs` is available as a variable
- `plasma-manager.homeManagerModules.plasma-manager` added to `modules`
- `extraSpecialArgs = { inherit inputs; }` passes inputs down to modules

### Step 1.2 — Create a minimal `nix/modules/plasma.nix`

Create the file with `programs.plasma.enable = true` and nothing else. This confirms the module is wired correctly without changing any settings:

```nix
{ ... }:

{
  programs.plasma = {
    enable = true;
    # Settings will be added incrementally in later phases
  };
}
```

### Step 1.3 — Add the import to `nix/home.nix`

```nix
imports = [
  ./modules/packages.nix
  ./modules/programs.nix
  ./modules/shell.nix
  ./modules/distrobox.nix
  ./modules/plasma.nix           # KDE Plasma settings
];
```

### Step 1.4 — Build and verify

```bash
# Lock the new input
cd ~/Documents/ESSENTIALS/installs
nix flake update plasma-manager

# Dry-run build (does not apply anything)
home-manager build --flake ./nix#boss

# If the build succeeds, apply
hms
```

At this point `programs.plasma.enable = true` with no settings is effectively a no-op — no Plasma files are modified. **Verify:** `home-manager switch` completes without errors. Log out and back in; confirm Plasma starts normally and all settings look identical to before.

### Step 1.5 — Commit the infrastructure

```bash
git add nix/flake.nix nix/flake.lock nix/home.nix nix/modules/plasma.nix
git commit -m "nix: wire up plasma-manager (no settings yet)"
```

---

## Phase 2 — Audit and capture current settings

Before writing Nix, understand what you currently have. This phase is read-only — no changes to the Nix config.

### Step 2.1 — Run rc2nix

`rc2nix` reads your live `~/.config/*.rc` files and emits a Nix declaration for every setting it recognises:

```bash
nix run github:nix-community/plasma-manager#rc2nix -- > /tmp/plasma-audit.nix
```

Open `/tmp/plasma-audit.nix` and review it. Expect:
- Many redundant default values (safe to delete)
- Some settings plasma-manager supports but you have at default (skip these)
- Some settings you actually care about (note these for Phase 3)
- Some settings rc2nix cannot express — these are the unmanaged remainder

### Step 2.2 — Identify what you care about

Go through System Settings and list the non-default configuration you have intentionally set. Common categories for this system:

**Appearance**
- [ ] Global color scheme (System Settings → Colors → Global Theme)
- [ ] Icon theme
- [ ] Cursor theme
- [ ] Wallpaper path (per-monitor if applicable)
- [ ] GTK application style (for Flatpak/non-KDE apps)

**Shortcuts**
- [ ] Virtual desktop switching shortcuts (Meta+1 through Meta+N)
- [ ] Window tiling shortcuts (if using KWin tiling)
- [ ] Custom application launch shortcuts
- [ ] Any overrides to default KWin shortcuts

**Panels**
- [ ] Primary panel: position, height, widget order
- [ ] Secondary monitor panel (if any)
- [ ] System tray pinned/hidden items
- [ ] Clock format

**Konsole**
- [ ] Default profile name
- [ ] Font and size
- [ ] Color scheme
- [ ] Scrollback lines
- [ ] Tab/split behaviour

**KRunner**
- [ ] Which runners are enabled
- [ ] Popup position (centre-screen or top)

**Input**
- [ ] Touchpad: tap-to-click, natural scroll, speed
- [ ] Mouse: acceleration, button mapping

**Window behaviour**
- [ ] Focus policy (click, focus-follows-mouse)
- [ ] Window rules for specific apps

**Screen locker**
- [ ] Lock timeout
- [ ] Lock on suspend

Cross-reference your list against the [plasma-manager options reference](https://nix-community.github.io/plasma-manager/) to confirm each item is supported before committing to managing it.

### Step 2.3 — Document the unmanaged remainder

For every setting you care about that rc2nix cannot express, add an entry to the table in `docs/limitations.md` under KDE Plasma Settings. This prevents surprises on a future reinstall.

---

## Phase 3 — Migrate settings incrementally

Migrate one category at a time. Each step is: write the Nix, apply, verify visually, commit. Never migrate multiple categories in a single commit — this makes it easy to bisect if something goes wrong.

### Step 3.1 — Workspace appearance

Add to `nix/modules/plasma.nix`:

```nix
programs.plasma = {
  enable = true;

  workspace = {
    colorScheme = "BreezeDark";          # exact name from System Settings
    # iconTheme  = "breeze-dark";
    # cursorTheme = "breeze_cursors";
    # wallpaper  = "/path/to/wallpaper.jpg";
    # wallpaperSlideShow.path = "/path/to/wallpapers/";
  };
};
```

Apply and verify:

```bash
hms
# Log out, log back in
# Open System Settings → Colors — confirm color scheme is correct
```

Commit: `git commit -m "plasma: set workspace appearance (color scheme, theme)"`

### Step 3.2 — Global keyboard shortcuts

Shortcut keys are declared as a map under `programs.plasma.shortcuts`. The left side is `"component"."action"`, the right side is the key combo string:

```nix
shortcuts = {
  kwin = {
    "Switch to Desktop 1" = "Meta+1";
    "Switch to Desktop 2" = "Meta+2";
    "Switch to Desktop 3" = "Meta+3";
    "Switch to Desktop 4" = "Meta+4";
    # Add others as needed
    # "Window Maximize"   = "Meta+PgUp";
  };
  # plasmashell."activate task manager entry 1" = "Meta+F1";
};
```

> **Note:** Ctrl+Alt+T and Print are known to be unreliable via plasma-manager. Manage these manually if needed.

Apply, log out/in, open System Settings → Shortcuts and verify each binding. Commit per logical group if there are many.

### Step 3.3 — Panel layout

Panel configuration is the most brittle area. Use `programs.plasma.panels`:

```nix
panels = [
  {
    location = "bottom";
    alignment = "center";
    height = 44;
    widgets = [
      "org.kde.plasma.kickoff"
      "org.kde.plasma.icontasks"
      "org.kde.plasma.marginsseperator"
      "org.kde.plasma.systemtray"
      "org.kde.plasma.digitalclock"
    ];
  }
];
```

The widget list must match what you actually have. Use rc2nix output or inspect `~/.config/plasma-org.kde.plasma.desktop-appletsrc` to find the exact applet IDs. Apply, log out/in, inspect the panel visually.

**If panel layout is complex or heavily customised** (multi-monitor, many widgets, custom plasmoids), consider skipping this category — the cost of maintaining it may outweigh the benefit. Document it as unmanaged in `docs/limitations.md`.

### Step 3.4 — KRunner

```nix
kRunner = {
  # position = "center";   # "top" or "center"
  activateWhenTypingOnDesktop = false;
};
```

Runner enable/disable is controlled per-plugin via `programs.plasma.configFile` for settings rc2nix exposes but plasma-manager has no typed option for. Check the options reference for what is and isn't available.

### Step 3.5 — Konsole

```nix
programs.konsole = {
  defaultProfile = "MyProfile";
  profiles = {
    "MyProfile" = {
      colorScheme = "Breeze";
      font = {
        name = "Hack Nerd Font Mono";
        size = 13;
      };
      scrollback = {
        lines = 10000;
      };
    };
  };
};
```

The profile name in `defaultProfile` must exactly match a key in `profiles`. Apply, open Konsole, verify font and color scheme.

### Step 3.6 — Input devices

```nix
input = {
  touchpad = {
    enable = true;
    tapToClick = true;
    naturalScroll = true;
    # scrollFactor = 1.0;
    # acceleration = 0.0;
  };
  # mouse = {
  #   acceleration = -0.5;
  # };
};
```

Apply, log out/in, verify touchpad behaviour in System Settings → Input Devices.

### Step 3.7 — Screen locker

```nix
screenLocker = {
  # lock = true;
  # lockOnResume = true;
  # timeout = 10;  # minutes
};
```

---

## Phase 4 — Handle what plasma-manager cannot manage

For every setting in your audit list that plasma-manager cannot express, pick one of:

### Option A: Commit the raw config files

For settings that are stable and rarely change, commit the relevant `~/.config/*.rc` file directly as a tracked file using Home Manager's `home.file`:

```nix
# In nix/modules/plasma.nix or a dedicated module
home.file.".config/kglobalshortcutsrc".source = ./files/kglobalshortcutsrc;
```

Store the source files at `nix/modules/files/` and commit them. This is fragile (KDE rewrites these files on every settings change) but ensures they're under version control.

### Option B: Use `programs.plasma.configFile` for raw INI writes

plasma-manager exposes an escape hatch for settings it doesn't model with typed options:

```nix
programs.plasma.configFile = {
  "kwinrc"."Compositing"."Backend" = "OpenGL";
  "kdeglobals"."KDE"."AnimationDurationFactor" = "0.5";
};
```

The format is `configFile."filename"."group"."key" = "value"`. Use the `~/.config/` filename without the path. Values are always strings.

### Option C: Accept them as unmanaged

If a setting is easy to reconfigure after a reinstall (two clicks in System Settings), it may not be worth the maintenance cost of tracking it. Document it in the unmanaged table in `docs/limitations.md`.

---

## Phase 5 — Update documentation

Once the migration is stable, update the docs to reflect the new state:

### `docs/limitations.md`

Update the KDE Plasma Settings entry:

```
| KDE Plasma settings | Partially in Nix | plasma-manager for supported settings; remainder documented below |
```

Add a sub-table of the specific settings that remain unmanaged and why.

### `docs/declarative-vs-imperative-state.md`

Move Plasma settings from the imperative/unmanaged column to the declarative column, with a note about partial coverage.

### `docs/daily-workflow.md`

Add a note to the "change Plasma settings" section: after changing settings in System Settings, reflect them back to Nix either via rc2nix or by editing `nix/modules/plasma.nix` directly, then commit.

---

## Rollback procedure

At any point during the migration:

**Rollback the Nix config:**
```bash
# Activate the previous Home Manager generation
home-manager generations         # list generations with timestamps
home-manager switch --switch-generation <N>
```

**Restore raw config files (if Plasma won't start):**
```bash
tar -xzf ~/plasma-config-backup-YYYYMMDD.tar.gz -C /
# Then log out and back in
```

**Remove plasma-manager entirely** (revert to Phase 0):
1. Remove `./modules/plasma.nix` from `nix/home.nix` imports
2. Remove the `plasma-manager` input from `nix/flake.nix`
3. Delete `nix/modules/plasma.nix`
4. Run `hms`

---

## Migration checklist

| Phase | Step | Status |
|-------|------|--------|
| 0 — Prep | Back up `~/.config/plasma*` and related files | |
| 1 — Infrastructure | Add `plasma-manager` input to `flake.nix` | |
| 1 — Infrastructure | Create minimal `nix/modules/plasma.nix` | |
| 1 — Infrastructure | Add import to `nix/home.nix` | |
| 1 — Infrastructure | `hms` builds and applies cleanly | |
| 1 — Infrastructure | Commit infrastructure (no settings) | |
| 2 — Audit | Run rc2nix, save output to `/tmp/plasma-audit.nix` | |
| 2 — Audit | Identify which settings to manage vs. leave unmanaged | |
| 2 — Audit | Document unmanaged remainder in `limitations.md` | |
| 3.1 — Migrate | Workspace appearance | |
| 3.2 — Migrate | Keyboard shortcuts | |
| 3.3 — Migrate | Panel layout | |
| 3.4 — Migrate | KRunner | |
| 3.5 — Migrate | Konsole | |
| 3.6 — Migrate | Input devices | |
| 3.7 — Migrate | Screen locker | |
| 4 — Remainder | Handle unmanaged settings (commit files / configFile / accept) | |
| 5 — Docs | Update `limitations.md`, `declarative-vs-imperative-state.md`, `daily-workflow.md` | |
