# buildFHSEnv

How Nix packages prebuilt binaries and GTK applications that require a standard Linux filesystem layout.

---

## What is buildFHSEnv?

Most Linux binaries are compiled with absolute paths to their dynamic linker (`/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`) and shared libraries. On a standard distro these paths exist. On Nix, everything lives under `/nix/store/<hash>-<name>/`, so a prebuilt binary expecting `/lib/ld-linux.so.2` will fail to start.

`buildFHSEnv` creates a lightweight FHS-compatible sandbox using `bubblewrap` (`bwrap`). Inside the sandbox, `/usr/lib`, `/lib`, `/bin`, and other standard paths contain the Nix-managed packages you specify. The application sees a normal Linux filesystem; from Nix's perspective everything is still hermetically managed.

The resulting derivation is a script that:
1. Builds an FHS rootfs in the Nix store (a merged view of specified packages at standard paths)
2. Calls `bwrap` to mount that rootfs over a subset of the host filesystem
3. Executes the target application inside the resulting namespace

```nix
pkgs.buildFHSEnv {
  name = "my-app";
  targetPkgs = pkgs: [ pkgs.my-app pkgs.some-lib ];
  runScript = "my-app";
}
```

`targetPkgs` populates the FHS environment — packages listed here appear at standard paths (`/usr/lib/`, `/usr/bin/`, etc.) inside the sandbox.

Official docs: https://ryantm.github.io/nixpkgs/builders/special/fhs-environments/

---

## buildFHSEnv vs. distrobox

| | `buildFHSEnv` | `distrobox` |
|---|---|---|
| **Purpose** | Run a single Nix-managed app needing FHS layout | Full container with its own distro's packages |
| **Isolation** | Filesystem view only (same user, same PID namespace) | OCI container (separate package manager, separate root) |
| **Package source** | nixpkgs | Host distro's apt/dnf inside the container |
| **Entry point** | Transparent — binary behaves like any other | Interactive shell or `distrobox -- command` |
| **State** | Fully declarative (Nix store); no mutable state | Container state in `~/.local/share/containers/` |
| **Use case** | Prebuilt binaries, GTK apps with typelib deps | Build toolchains, distro-specific tools |

Use `buildFHSEnv` when a Nix-packaged application needs FHS paths to function. Use `distrobox` when you need a full Ubuntu or Fedora environment with that distro's package manager.


## Most popular nixpkgs packages using buildFHSEnv:

Gaming

- Steam — the canonical example; also exposes steam-run for running arbitrary binaries in the same FHS env
- Lutris — game launcher wrapping Wine/Proton runners
- Wine / wineWowPackages — 32+64-bit Wine stacks for Windows game compatibility

IDEs & Dev Tools

- Android Studio — uses buildFHSUserEnv with ncurses5 and related libs
- CUDA dev shells — buildFHSUserEnv for cudatoolkit + NVIDIA driver combos
- ML/AI environments — Python + CUDA + cuDNN + TensorRT chains

Proprietary / Commercial Software

- MATLAB — recommended approach is buildFHSUserEnv in a shell.nix
- Mathematica — similar pattern
- Unity Hub — game dev platform with FHS-hardcoded expectations

Graphics

- blender-bin — prebuilt binary variant (as opposed to the source-built blender)

### Why these need FHS

┌────────────────────────────────────────────────────┬─────────────────────────────────────────┐
│                       Reason                       │                Examples                 │
├────────────────────────────────────────────────────┼─────────────────────────────────────────┤
│ Precompiled binaries with hardcoded /usr/lib paths │ Steam, blender-bin, Unity Hub           │
├────────────────────────────────────────────────────┼─────────────────────────────────────────┤
│ Self-updating sub-package managers                 │ Android SDK tools, npm/pip in CUDA envs │
├────────────────────────────────────────────────────┼─────────────────────────────────────────┤
│ Integrity-verified binaries that can't be patched  │ MATLAB, Mathematica                     │
├────────────────────────────────────────────────────┼─────────────────────────────────────────┤
│ 32-bit compatibility layers                        │ Wine, wineWowPackages                   │
└────────────────────────────────────────────────────┴─────────────────────────────────────────┘

**Note**: The modern alternative is **nix-ld**, which intercepts the ELF dynamic linker rather than creating a full chroot — it's less isolated but easier to use
interactively. buildFHSEnv (bubblewrap-based since NixOS 23.11, replacing the old user-namespace setuid approach) remains the standard for packages that
need a complete FHS tree.

---

## This repo's uses

### Lutris

Lutris's nixpkgs derivation already uses `buildFHSEnv` to create an FHS sandbox for the Lutris Python/GTK process and game runners. The `extraPkgs` and `extraLibraries` override arguments allow injecting additional packages into that sandbox.

**The problem**

Lutris uses `AyatanaAppIndicator3` (system tray icon) via GObject Introspection. Python-gi loads typelibs (`.typelib` files) from `GI_TYPELIB_PATH` and a set of standard paths including `/usr/lib/girepository-1.0/`. On a non-NixOS system, `libayatana-appindicator` installs its typelib to a Nix store path, not `/usr/lib/girepository-1.0/`. Without intervention, Python-gi cannot find it. Tracked in [nixpkgs#503530](https://github.com/NixOS/nixpkgs/issues/503530).

**Current approach**

```nix
(symlinkJoin {
  name = "lutris";
  paths = [ (lutris.override {
    extraPkgs      = pkgs: [ pkgs.libayatana-appindicator pkgs.procps ];
    extraLibraries = pkgs: [ pkgs.libayatana-appindicator ];
  }) ];
  buildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/lutris \
      --prefix GI_TYPELIB_PATH : "${libayatana-appindicator}/lib/girepository-1.0"
  '';
})
```

**Why `extraPkgs` alone isn't enough**

`extraPkgs` adds `libayatana-appindicator` to the FHS rootfs, placing the typelib at `/usr/lib64/girepository-1.0/` (the Lutris FHS env uses `/usr/lib64/` for 64-bit packages). Python-gi's default search path includes `/usr/lib/girepository-1.0/` but not `/usr/lib64/girepository-1.0/`, so the typelib is still not found — confirmed by the tray icon being absent at runtime.

The `wrapProgram --prefix GI_TYPELIB_PATH` fix sets `GI_TYPELIB_PATH` to the Nix store path of the typelib on the outer bwrap launch script (before the sandbox starts). The env var persists into the bwrap namespace where Python runs, and Python-gi finds the typelib via `GI_TYPELIB_PATH`. This is the minimum that works.

`extraLibraries` adds the `.so` to the FHS library path (needed so the shared library loads at runtime). `extraPkgs` adds the full package including `procps` (`pgrep`). Both are needed alongside `wrapProgram`.

**`procps`**: Lutris's per-game bwrap overlays `/usr/bin` with its own Nix store version of binaries. Without procps in `extraPkgs`, `pgrep` is missing from that overlay. `procps` also remains as a standalone `home.packages` entry for host-side use — both are needed.

**Nested bwrap**

Lutris's Python process runs inside the outer FHS sandbox. When Lutris launches a game, it creates an inner bwrap sandbox around the game runner — two levels of `bwrap`. This works on Ubuntu 24.04 (kernel 6.x) because unprivileged user namespaces are enabled:

```bash
sysctl kernel.unprivileged_userns_clone
# Should be: 1
```

---

### Android Studio

Android Studio bundles a JDK, SDK tools, and an emulator as prebuilt binaries with hardcoded `/lib/ld-linux.so.2` interpreter paths. `patchelf` cannot reliably fix these.

The `androidStudioPackages.stable` nixpkgs package wraps Android Studio in its own `buildFHSEnv` environment providing `ncurses5`, TLS certificates (for Flutter compatibility), and libraries for graphics and audio. No custom Nix configuration is required:

```nix
androidStudioPackages.stable
```

`ANDROID_HOME` is set in `shell.nix` (`$HOME/Documents/Dev/Android/Sdk`). Android Studio reads this on launch and uses the SDK at that path. The SDK Manager downloads new components there; no existing SDK data is lost.

The IDE binary is named `android-studio` (not `studio.sh` as in the PPA install).

**Cleaning up the PPA install** (after confirming the Nix version works):

```bash
sudo apt remove android-studio
sudo add-apt-repository --remove ppa:maarten-fonville/android-studio
```

---

## Limitations and gotchas

**Not for system services.** `buildFHSEnv` wraps a single executable. It cannot manage a daemon, socket-activated service, or D-Bus service — those need system-level `systemd` integration outside any user-space bwrap sandbox.

**FHS rootfs is read-only.** The rootfs is mounted `--ro-bind` via bwrap. Applications cannot install or write files under `/usr/lib/` inside the sandbox; they use their normal data directories (`~/.config/`, `~/.local/share/`) which are bind-mounted from the host as read-write.

**`extraPkgs` vs. `extraLibraries`.** When overriding a package that uses `buildFHSEnv` internally:
- Use `extraPkgs` to add a package whose typelibs, executables, or data files need to be inside the sandbox
- Use `extraLibraries` only when you specifically need additional `.so` files on the library search path
- For GObject Introspection typelibs, always use `extraPkgs`

**When NOT to use buildFHSEnv.** If a Nix-compiled package links against `/nix/store/` paths, it does not need `buildFHSEnv`. Use it only for: prebuilt binaries without source, applications that `dlopen` libraries from hardcoded paths, and GTK/GObject apps that search for typelibs at `/usr/lib/girepository-1.0/`.
