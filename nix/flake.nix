{
  description = "Home Manager configuration for boss's Kubuntu system";

  inputs = {
    # Pinned to a commit at least PIN_AGE_DAYS days old on its upstream branch
    # (see update.sh). The age-pin gives Hydra time to fully populate its
    # binary cache, so home-manager switch downloads pre-built artifacts
    # rather than compiling from source. The `# channel:` comment above each
    # url records the upstream branch so update.sh can advance the pin on the
    # next run; the SHA in the url is what nix flake update resolves into
    # flake.lock. Don't hand-edit the SHAs — let update.sh do it.

    # channel: nixos-26.05
    nixpkgs.url = "github:NixOS/nixpkgs/c56a87d8e41ce69bd2af57eb35dcc117a9dfca33";

    # channel: nixos-unstable
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/1d060086d60cb76a40cf37109f979d88a5bd6396";

    # Bleeding-edge nixpkgs for individual packages that need a newer version
    # than the age-pinned `nixpkgs-unstable` above can offer — used when a
    # feature lands in unstable but hasn't reached the age-pin yet (scrcpy 5.x
    # used this until unstable caught up). Tracks the nixos-unstable branch
    # HEAD; bump alone with:
    #   nix flake update nixpkgs-latest --flake ~/Projects/installs/nix
    # To use it, pass `pkgs-latest = import nixpkgs-latest { ... }` through
    # extraSpecialArgs like pkgs-unstable. Not advanced by update.sh's regular
    # age-pin cycle unless added there — bump deliberately, and expect Hydra
    # cache misses (possible local source builds) on fresh bumps.
    # channel: nixos-unstable
    nixpkgs-latest.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      # channel: release-26.05
      url = "github:nix-community/home-manager/24f2190587513b9c2f73db112a17844ae912d965";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management — decrypts age-encrypted secrets (nix/secrets/*.yaml)
    # at activation. Used by modules/rclone.nix for rclone remote credentials.
    sops-nix = {
      # channel: master
      url = "github:Mic92/sops-nix/fe7b4228405aeac2ce7192c2049a6e2bc8637082";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # claude-desktop — removed; was github:aaddrick/claude-desktop-debian.
    # The flake rebuilt a Debian .deb on every lock bump. Now installed via
    # custom-installers.yml from the upstream .deb release.

    # AI coding tools — own binary cache at cache.numtide.com, rebuilt daily.
    # Age-pinned to a ≥PIN_AGE_DAYS_LLM_AGENTS-day-old commit (see update.sh) so
    # a `nix flake update` never lands on a same-day commit numtide hasn't
    # published a cache for yet — that forced hms to compile its CLIs
    # locally instead of downloading. The pin floor is much shorter than
    # nixpkgs' PIN_AGE_DAYS since numtide's cache catches up within a day.
    # Also intentionally NOT following nixpkgs so the pre-built packages in
    # numtide's cache (built against unstable) remain valid store paths.
    # channel: main
    llm-agents.url = "github:numtide/llm-agents.nix/b2700a2b5e7b94649dd960d08ea3b2304d91b2bc";

    # Third-party inputs below (and sops-nix above) are age-pinned too, but for
    # a different reason: a supply-chain cooldown rather than cache coverage.
    # A compromised or broken upstream commit gets PIN_AGE_DAYS_SOURCE days
    # (orca: PIN_AGE_DAYS_ORCA) to be noticed before update.sh adopts it.
    # channel: master
    tuxManager.url = "github:benapetr/TuxManager/1cb8ec247cebd1ff093cb1239db570c0f7057e8f";
    tuxManager.inputs.nixpkgs.follows = "nixpkgs";

    # channel: master
    ie-r.url = "github:miaupaw/ie-r/d8f61e36087f6ade97f5cd88b43bb5554739c1c3";

    # Zed's Delta (official prebuilt Linux binaries, wrapped for Nix).
    # channel: main
    delta.url = "github:zed-industries/delta-nix/5749237bd9c9da0661e5480bcc0301968fcf039d";
    delta.inputs.nixpkgs.follows = "nixpkgs";

    # Orca agent skills (skills/orca-cli, skills/orchestration) — source only,
    # linked into ~/.claude/skills by modules/agent-skills.nix. Shorter pin
    # window than the others: the Orca app (AppMan) updates freely, and the
    # skills shouldn't lag its CLI by long.
    orca = {
      # channel: main
      url = "github:stablyai/orca/5f95146feaaf88aa806bbfd786967c7b63cffc4b";
      flake = false;
    };

    # Context7 find-docs skill (skills/find-docs, drives `npx ctx7@latest`) — source only,
    # linked by modules/agent-skills.nix. Replaces the Context7 MCP server.
    context7 = {
      # channel: master
      url = "github:upstash/context7/5c4a4b43cd5010f5678c6fceac3dd16865112e67";
      flake = false;
    };

    # REA reverse-engineer-anything skill (.agents/skills/reverse-engineer-anything,
    # github:morluto/rea) — source only, linked by modules/agent-skills.nix.
    # The repo's other .agents/skills/rea-* skills are for developing REA itself.
    rea = {
      # channel: main
      url = "github:morluto/rea/bbe2bcc979be747698d9ad9ce87af017b92e0f10";
      flake = false;
    };

    # Impeccable design skill (github:pbakaus/impeccable) — source only.
    # agent-skills.nix links its per-harness builds (.claude/.opencode/.agents
    # skills/impeccable) into the matching skill dirs. The skill itself is
    # instructions + scripts; its engine binary self-downloads on first run to
    # ~/.impeccable/bin/, outside the read-only store path. Desktop-only.
    impeccable = {
      # channel: main
      url = "github:pbakaus/impeccable/0226a6f551eb39824c9cbc97547e56a80a508fdc";
      flake = false;
    };

    # CLI-Anything (github:HKUDS/CLI-Anything) — source only. agent-skills.nix links
    # its cli-hub-meta-skill into the skill dirs and its opencode-commands/ + HARNESS.md
    # into the OpenCode commands dirs; ai-agents.nix registers the repo as a Claude
    # Code plugin marketplace and enables the cli-anything plugin. The companion
    # `cli-hub` binary is the cli-anything-hub PyPI package in uv-tools.txt.
    cli-anything = {
      # channel: main
      url = "github:HKUDS/CLI-Anything/34f519533bc175d2fe287ab8316b0dd99bb9cc43";
      flake = false;
    };

    # Cloudflare security-audit skill (github:cloudflare/security-audit-skill) —
    # source only. agent-skills.nix links skills/security-audit into the skill
    # dirs. Multi-phase security audit workflow; runs its zero-dep .cjs
    # validators with plain node. Server-safe: audits read source only.
    security-audit-skill = {
      # channel: main
      url = "github:cloudflare/security-audit-skill";
      flake = false;
    };

    # Own Logseq fork (github.com/VictorVow/logseq) — source only, tracked at its `fork`
    # branch. agent-skills.nix links .agents/skills/logseq-cli from it into
    # ~/.claude/skills + ~/.agents/skills, so the skill tracks the same branch the
    # locally-built `logseq` CLI is compiled from. Advances via update.sh like the
    # other source-only inputs.
    logseq-fork = {
      # channel: fork
      url = "github:VictorVow/logseq/399025dc502ec70cce42a0928cdbebf877a896f6";
      flake = false;
    };

    # Nix User Repository — provides rycee's firefox-addons set (617 pre-packaged
    # Firefox extensions with addonId passthru) for declarative profile
    # extensions. Only the firefox-addons subset is used.
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Notifications desktop receiver — Home Manager module + the notify CLI from
    # the self-hosted Notifications repo on Forgejo (tailnet-only, public so a
    # git+https fetch needs no token). Imported in home.nix as
    # notifications.homeManagerModules.desktop.
    notifications = {
      url = "git+https://git.device.example.com/self-hosted/Notifications.git";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-latest, home-manager, llm-agents, tuxManager, ie-r, delta, sops-nix, orca, context7, logseq-fork, rea, impeccable, cli-anything, security-audit-skill, nur, notifications, ... }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    # Independently-pinned nixos-unstable HEAD (see the input comment), passed
    # to modules as pkgs-latest for packages that can't wait for the age pin.
    pkgs-latest = import nixpkgs-latest {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
    # devin-cli pin override. Cognition unpublishes a version's tarball from
    # static.devin.ai (HTTP 403 on the whole path) shortly after promoting the
    # next one to cli/current/manifest.json, so nixpkgs-unstable's pinned
    # version (3000.11.234) can't be fetched at all — even the older tarballs
    # we built from are gone. Track the live manifest instead. Hashes below
    # come from that manifest's platforms.<target>.sha256 (hex → SRI base64).
    devinVersion = "3000.14.30821";
    devinTargets = {
      x86_64-linux  = { target = "x86_64-unknown-linux";  hash = "sha256-TcQ+PkOIus5g/iqoAQy7OZQC5ySJLXF1hFsc3vAOfds="; };
      aarch64-linux = { target = "aarch64-unknown-linux"; hash = "sha256-PeuK9rAmBg6XXtNxk24TmBgCDl3Fq7y6B83gOfRzpaU="; };
    };
    mkUnstable = system: (import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    }).extend (_final: prev: {
      devin-cli = prev.devin-cli.overrideAttrs (_: {
        version = devinVersion;
        src = prev.fetchurl {
          url = "https://static.devin.ai/cli/${devinVersion}/devin-${devinVersion}-${devinTargets.${system}.target}.tar.gz";
          inherit (devinTargets.${system}) hash;
        };
      });
    });

    # The flake lives in nix/, but sourceInfo is the whole repo — needed so
    # the checks can see the shell scripts and playbooks at the repo root.
    repo = self.sourceInfo.outPath;
    lint = name: tools: script: pkgs.runCommand "check-${name}" { nativeBuildInputs = tools; } ''
      cd ${repo}
      ${script}
      touch $out
    '';
  in {
    # `nix fmt` — for new/touched files only; the existing code keeps its
    # hand-aligned style, so don't run it over the whole tree.
    formatter.x86_64-linux = pkgs.nixfmt;

    # Lint tools for `just check` and .githooks/pre-commit.
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [ just statix deadnix nixfmt shellcheck yamllint ansible-lint ];
    };

    # `nix flake check` (or `just check`, which adds the Ansible linters).
    checks.x86_64-linux = {
      # Full HM builds: catches eval errors and broken packages before `hms`.
      hm-build       = self.homeConfigurations."boss".activationPackage;
      hm-build-lord  = self.homeConfigurations."lord".activationPackage;
      statix = lint "statix" [ pkgs.statix ] "statix check -c nix/statix.toml nix";
      deadnix = lint "deadnix" [ pkgs.deadnix ] "deadnix --fail nix";
      shellcheck = lint "shellcheck" [ pkgs.shellcheck pkgs.git pkgs.findutils ] ''
        find . -name '*.sh' -not -path './docs/archive/*' -print0 \
          | xargs -0 shellcheck -x -S warning
      '';
    };

    # Only checkable on the VM itself (or an aarch64 remote builder):
    # `nix flake check` on x86_64 ignores other systems. Eval sanity from the
    # desktop: nix eval .#homeConfigurations.droid.activationPackage
    checks.aarch64-linux.hm-build-droid = self.homeConfigurations."droid".activationPackage;

    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home.nix sops-nix.homeManagerModules.sops ];

      extraSpecialArgs = {
        inherit llm-agents tuxManager ie-r delta orca context7 logseq-fork rea impeccable cli-anything security-audit-skill nur notifications pkgs-latest;
        # import (not legacyPackages) so allowUnfree applies — home.nix's
        # nixpkgs.config only reaches the main pkgs set. mkUnstable adds the
        # devin-cli live-version override (see the let block).
        pkgs-unstable = mkUnstable "x86_64-linux";
        hostProfile = {
          isServer = false;
          hms = {
            flakePath  = "$HOME/Projects/installs/nix";
            configName = "boss";
          };
        };
      };
    };

    # lord-ubuntu headless server — see docs/system/lord-ubuntu-home.md.
    # Reuses the desktop modules where they're headless-safe (shell-apps,
    # ai-agents-server, cass) via parallel home-lord.nix + *-server.nix modules.
    homeConfigurations."lord" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home-lord.nix sops-nix.homeManagerModules.sops ];

      extraSpecialArgs = {
        inherit llm-agents tuxManager ie-r delta orca context7 logseq-fork rea impeccable cli-anything security-audit-skill notifications pkgs-latest;
        pkgs-unstable = mkUnstable "x86_64-linux";
        hostProfile = {
          isServer = true;
          hms = {
            flakePath  = "$HOME/installs/nix";
            configName = "lord";
          };
        };
      };
    };

    # droid — Pixel 8 AVF "Linux Terminal" Debian VM (aarch64-linux). Minimal
    # headless set: reuses the server modules, minus the ones that assume a
    # real server (cass, systemd-creds sops key, update-all/cass timers).
    homeConfigurations."droid" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-linux;

      modules = [ ./home-droid.nix sops-nix.homeManagerModules.sops ];

      extraSpecialArgs = {
        inherit llm-agents orca context7 logseq-fork rea impeccable cli-anything security-audit-skill;
        pkgs-unstable = mkUnstable "aarch64-linux";
        hostProfile = {
          isServer = true;
          hms = {
            flakePath  = "$HOME/installs/nix";
            configName = "droid";
          };
        };
      };
    };
  };
}
