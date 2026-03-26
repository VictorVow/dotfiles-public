# nix-ld

> **Decision:** Not applicable — nix-ld is NixOS-only. On non-NixOS (this system), the dynamic linker already exists at the standard FHS paths; installing nix-ld there would break the OS. The equivalent problem is already handled by `buildFHSEnv` and `targets.genericLinux.enable`.

[`nix-community/nix-ld`](https://github.com/nix-community/nix-ld) · [`wiki.nixos.org/wiki/Nix-ld`](https://wiki.nixos.org/wiki/Nix-ld)

---

## What is nix-ld?

Most Linux binaries have a hardcoded ELF interpreter path in their header — the path to the dynamic linker that the kernel must find before the binary can start. On standard Linux this is `/lib64/ld-linux-x86-64.so.2`. On NixOS, that path does not exist; everything is in `/nix/store/<hash>/`.

nix-ld places a shim at the standard linker path. When an unpatched binary is executed, the kernel finds nix-ld's shim instead. The shim reads the `NIX_LD` environment variable (which points to a real glibc linker in the Nix store), translates `NIX_LD_LIBRARY_PATH` into `LD_LIBRARY_PATH`, and hands off to the real linker. The binary runs without being patched.

```
kernel sees /lib64/ld-linux-x86-64.so.2
    → runs nix-ld shim
        → reads $NIX_LD → loads /nix/store/.../ld-linux-x86-64.so.2
        → reads $NIX_LD_LIBRARY_PATH → sets $LD_LIBRARY_PATH
        → executes binary with correct linker + libraries
```

NixOS configuration:

```nix
programs.nix-ld.enable = true;
programs.nix-ld.libraries = with pkgs; [
  stdenv.cc.cc  # libstdc++
  zlib
  openssl
  curl
  # ... add libraries as each binary needs them
];
```

---

## nix-ld vs. buildFHSEnv

Both solve the same core problem (unpatched binaries that expect FHS paths), but with different mechanisms and tradeoffs:

| | `nix-ld` | `buildFHSEnv` |
|---|---|---|
| **Mechanism** | Shim at standard linker path; no namespace | Full FHS tree mounted via `bwrap` namespace |
| **Scope** | System-wide; affects all unpatched binaries | Per-application; isolated sandbox |
| **Invocation** | Transparent — binary runs directly | Wraps binary in a launcher script |
| **setuid binaries** | Supported | Not supported |
| **Nesting** | Works inside `bwrap`, `nix build`, direnv | Cannot nest another `buildFHSEnv` inside |
| **Library config** | Manual: add libraries to `NIX_LD_LIBRARY_PATH` | Declarative: `targetPkgs` / `multiPkgs` |
| **Library leakage** | `LD_LIBRARY_PATH` affects all child processes | Contained — only affects the sandbox |
| **OS requirement** | **NixOS only** | Any Nix installation, including non-NixOS |
| **Integrity-checked binaries** | Works — binary not modified | Works — binary not modified |
| **Patched Nix binaries** | Not needed (they have RPATH set) | Not needed |

**In practice on NixOS:** nix-ld is the lighter, lower-friction option for running individual prebuilt binaries ad-hoc. `buildFHSEnv` is used when packages need a complete, reproducible FHS environment — games, IDEs, anything requiring a curated library set.

---

## Why it does not apply to this system

This system runs **Kubuntu (non-NixOS)**. The standard dynamic linker paths already exist and are actively used by the Ubuntu system:

```
/lib64/ld-linux-x86-64.so.2   → Ubuntu's glibc linker (used by every apt package)
/lib/x86_64-linux-gnu/         → Ubuntu's system libraries
```

nix-ld would need to overwrite `/lib64/ld-linux-x86-64.so.2` with its shim to intercept binary execution. Doing so would immediately break every Ubuntu binary on the system, since the shim would look for `NIX_LD` which is not set for system processes.

There is no supported path for running nix-ld on non-NixOS. The `programs.nix-ld` Home Manager module does not exist for non-NixOS configurations — it is a NixOS module only, exposed via `nixosModules.nix-ld`.

### What this system uses instead

The same class of problem — prebuilt binaries that need FHS libraries — is already solved on this system:

| Problem | Tool | Where |
|---------|------|--------|
| Prebuilt binaries with hardcoded `/lib/ld-linux.so.2` | `buildFHSEnv` (internal to nixpkgs packages) | `androidStudioPackages.stable` in `packages.nix` |
| Lutris FHS sandbox for Python/GTK + game runners | `buildFHSEnv` (internal to `lutris` nixpkgs) | `packages.nix` Gaming section |
| Nix store libs visible to GPU/OpenGL paths | `targets.genericLinux.enable = true` | `home.nix` |
| Ecosystem-specific tools needing their distro's linker | `distrobox` containers | `distrobox.nix` |
| Brew-installed binaries that expect FHS | Ubuntu's native FHS (already present) | System |

`targets.genericLinux.enable = true` (already active in `home.nix`) addresses part of the same use case for Nix-compiled packages by creating `/run/opengl-driver` → Nix Mesa derivation, so GPU-dependent Nix packages find the driver. This is the closest non-NixOS equivalent, and it only covers what Home Manager can manage.

---

## If this system migrated to NixOS

nix-ld would become directly useful. The primary beneficiaries would be:

- **Homebrew-installed binaries** — Homebrew on NixOS would not work cleanly; nix-ld would let prebuilt tarballs run without `patchelf`.
- **AI CLI tools** (Cline, Copilot CLI, Gemini CLI, etc.) — currently installed via npm to `~/.npm-global`. Their bundled Node binary stubs and native addons use the system linker path. On NixOS with nix-ld, these would run without a `buildFHSEnv` wrapper.
- **Android SDK tools** — currently handled by `androidStudioPackages.stable`'s internal `buildFHSEnv`. On NixOS with nix-ld, the raw Nix package might work without a custom FHS wrapper.
- **Language version managers** (fnm, pyenv, dnvm) — these download prebuilt binaries; nix-ld would let them run transparently.

Even on NixOS, `buildFHSEnv` would still be needed for applications that require a fully populated FHS tree rather than just linker resolution (Steam, Lutris, Wine). nix-ld solves the linker path; `buildFHSEnv` solves the entire filesystem layout.

---

## Key caveats (for future reference)

**Nix-compiled binaries don't use nix-ld.** Packages built by Nix have RPATH set to `/nix/store/...` paths and call the Nix-store linker directly. `NIX_LD_LIBRARY_PATH` has no effect on them. This means running e.g. `python3 -c "import ctypes; ctypes.CDLL('libcurl.so.4')"` in a nix-ld environment won't work — Python itself is a Nix binary and ignores `LD_LIBRARY_PATH` that nix-ld sets.

**`LD_LIBRARY_PATH` leaks into child processes.** Unlike `buildFHSEnv`'s contained sandbox, nix-ld's library paths propagate to every subprocess. This can cause libraries from `NIX_LD_LIBRARY_PATH` to be loaded by properly built Nix applications, potentially causing version conflicts. The nix-ld-rs rewrite (now merged into the main project) mitigates this with environment isolation on `x86_64-linux`.

**Per-binary library discovery.** Unlike `buildFHSEnv` which declares a complete environment upfront, nix-ld requires iterating: run binary, see which library is missing, find the nixpkgs package that provides it, add to `programs.nix-ld.libraries`, rebuild. Tools like `nix-index` (`nix-locate lib/libcurl.so.4`) help.
