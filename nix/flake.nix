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
    nixpkgs.url = "github:NixOS/nixpkgs/6fcc160353f63555b560f25588925133c8f61f2a";

    # channel: nixos-unstable
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/6510408d147d8c5e6d76043e899e9251756f6a75";

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
      url = "github:nix-community/home-manager/db7d5e2332710f5abb088f6b5de927d7f9511b35";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management — decrypts age-encrypted secrets (nix/secrets/*.yaml)
    # at activation. Used by modules/rclone.nix for rclone remote credentials.
    sops-nix = {
      # channel: master
      url = "github:Mic92/sops-nix/a1438ca361b05d1e70854d5495abcb34fdf6ff47";
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
    llm-agents.url = "github:numtide/llm-agents.nix/ea188d2f072e0ec8d5b71245e228803672801a22";

    # Third-party inputs below (and sops-nix above) are age-pinned too, but for
    # a different reason: a supply-chain cooldown rather than cache coverage.
    # A compromised or broken upstream commit gets PIN_AGE_DAYS_SOURCE days
    # (orca: PIN_AGE_DAYS_ORCA) to be noticed before update.sh adopts it.
    # channel: master
    tuxManager.url = "github:benapetr/TuxManager/305bcadbc2d1ec00689e4827041700ed0ca8341f";
    tuxManager.inputs.nixpkgs.follows = "nixpkgs";

    # channel: master
    ie-r.url = "github:miaupaw/ie-r/016b62ecb21f3e0cf900b5907aba52ce5608c062";

    # Zed's Delta (official prebuilt Linux binaries, wrapped for Nix).
    # channel: main
    delta.url = "github:zed-industries/delta-nix/6091b4eb4a0d41ab2b23f039b991683a6181535f";
    delta.inputs.nixpkgs.follows = "nixpkgs";

    # Orca agent skills (skills/orca-cli, skills/orchestration) — source only,
    # linked into ~/.claude/skills by modules/agent-skills.nix. Shorter pin
    # window than the others: the Orca app (AppMan) updates freely, and the
    # skills shouldn't lag its CLI by long.
    orca = {
      # channel: main
      url = "github:stablyai/orca/30733ac703b43f35bfa2a7c0339a09b316e69b99";
      flake = false;
    };

    # Context7 find-docs skill (skills/find-docs, drives `npx ctx7@latest`) — source only,
    # linked by modules/agent-skills.nix. Replaces the Context7 MCP server.
    context7 = {
      # channel: master
      url = "github:upstash/context7/ae4871e9a8cbed00bc0f4a40b0b5b61e2d37378c";
      flake = false;
    };

    # REA reverse-engineer-anything skill (.agents/skills/reverse-engineer-anything,
    # github:morluto/rea) — source only, linked by modules/agent-skills.nix.
    # The repo's other .agents/skills/rea-* skills are for developing REA itself.
    rea = {
      # channel: main
      url = "github:morluto/rea/69fe86c5c7c31082d1846842b3afd00343499d75";
      flake = false;
    };

    # Impeccable design skill (github:pbakaus/impeccable) — source only.
    # agent-skills.nix links its per-harness builds (.claude/.opencode/.agents
    # skills/impeccable) into the matching skill dirs. The skill itself is
    # instructions + scripts; its engine binary self-downloads on first run to
    # ~/.impeccable/bin/, outside the read-only store path. Desktop-only.
    impeccable = {
      # channel: main
      url = "github:pbakaus/impeccable/0665bd812ae0908fcab17b96fd4f840defb882d9";
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

    # Notifications desktop receiver — Home Manager module + the notify CLI from
    # the self-hosted Notifications repo on Forgejo (tailnet-only, public so a
    # git+https fetch needs no token). Imported in home.nix as
    # notifications.homeManagerModules.desktop.
    notifications = {
      url = "git+https://git.device.example.com/self-hosted/Notifications.git";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-latest, home-manager, llm-agents, tuxManager, ie-r, delta, sops-nix, orca, context7, logseq-fork, rea, impeccable, cli-anything, security-audit-skill, notifications, ... }:
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
        inherit llm-agents tuxManager ie-r delta orca context7 logseq-fork rea impeccable cli-anything security-audit-skill notifications pkgs-latest;
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
        inherit llm-agents tuxManager ie-r delta orca context7 logseq-fork rea impeccable cli-anything security-audit-skill;
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
