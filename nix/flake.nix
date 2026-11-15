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
    nixpkgs.url = "github:NixOS/nixpkgs/fa1373130d5a21c040a47c5dbe1913d59ed91808";

    # channel: nixos-unstable
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/1c89083e451e891152365b799595cf7790a43325";

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
      url = "github:Mic92/sops-nix/89a234ce2daf6e568a7d4b4fe250afdd23d84e20";
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
    llm-agents.url = "github:numtide/llm-agents.nix/ee05b5abb7c7f4af84a5ad5420f8a6e662774f2b";

    # Third-party inputs below (and sops-nix above) are age-pinned too, but for
    # a different reason: a supply-chain cooldown rather than cache coverage.
    # A compromised or broken upstream commit gets PIN_AGE_DAYS_SOURCE days
    # (orca: PIN_AGE_DAYS_ORCA) to be noticed before update.sh adopts it.
    # channel: master
    tuxManager.url = "github:benapetr/TuxManager/4bc67f81684b9a135bf533668fa7d326acb6cf2e";
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
      url = "github:stablyai/orca/e81a89c5ffe3e8bf8abcc962630ee1fdbc2139ad";
      flake = false;
    };

    # Context7 find-docs skill (skills/find-docs, drives `npx ctx7@latest`) — source only,
    # linked by modules/agent-skills.nix. Replaces the Context7 MCP server.
    context7 = {
      # channel: master
      url = "github:upstash/context7/078c0c731d19eb88d2391b236ab82a127dbabac3";
      flake = false;
    };

    # REA reverse-engineer-anything skill (.agents/skills/reverse-engineer-anything,
    # github:morluto/rea) — source only, linked by modules/agent-skills.nix.
    # The repo's other .agents/skills/rea-* skills are for developing REA itself.
    rea = {
      # channel: main
      url = "github:morluto/rea/72d5e72e6d7b7997c4ecb11972fc405be8ec67d2";
      flake = false;
    };

    # Impeccable design skill (github:pbakaus/impeccable) — source only.
    # agent-skills.nix links its per-harness builds (.claude/.opencode/.agents
    # skills/impeccable) into the matching skill dirs. The skill itself is
    # instructions + scripts; its engine binary self-downloads on first run to
    # ~/.impeccable/bin/, outside the read-only store path. Desktop-only.
    impeccable = {
      # channel: main
      url = "github:pbakaus/impeccable/e6daaba727fc444f1534e7d7cd7ea88942565b7d";
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

    homeConfigurations."boss" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      modules = [ ./home.nix sops-nix.homeManagerModules.sops ];

      extraSpecialArgs = {
        inherit llm-agents tuxManager ie-r delta orca context7 logseq-fork rea impeccable cli-anything security-audit-skill nur notifications pkgs-latest;
        # import (not legacyPackages) so allowUnfree applies — home.nix's
        # nixpkgs.config only reaches the main pkgs set.
        pkgs-unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
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
        pkgs-unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        hostProfile = {
          isServer = true;
          hms = {
            flakePath  = "$HOME/installs/nix";
            configName = "lord";
          };
        };
      };
    };
  };
}
