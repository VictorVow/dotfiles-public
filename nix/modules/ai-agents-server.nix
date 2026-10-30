{
  pkgs,
  lib,
  llm-agents,
  ...
}:

# Server variant of ai-agents.nix — headless lord-ubuntu.
# Same agent CLIs and global policies as desktop, minus the browser MCPs
# (firefox-devtools, chromium-devtools — no browsers installed).
let
  jsonFormat = pkgs.formats.json { };

  nixosMcp = {
    command = "uvx";
    args = [ "mcp-nixos" ];
  };

  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Same permission/secret-guard policy as desktop ai-agents.nix. Keep in sync —
  # the policy is identical on both hosts because the same threat model applies
  # (agents with file-read + shell access on a box that holds the repo's sops
  # secrets).
  opencodePermissions = [
    {
      action = "external_directory";
      resource = "*";
      effect = "allow";
    }
    {
      action = "read";
      resource = "*.env";
      effect = "deny";
    }
    {
      action = "read";
      resource = "*.env.*";
      effect = "deny";
    }
    {
      action = "read";
      resource = "*.env.example";
      effect = "allow";
    }
    {
      action = "read";
      resource = "*.env.*.example";
      effect = "allow";
    }
    {
      action = "read";
      resource = "*.env.example.*";
      effect = "allow";
    }
    {
      action = "read";
      resource = "*.pem";
      effect = "deny";
    }
    {
      action = "read";
      resource = "*.key";
      effect = "deny";
    }
    {
      action = "read";
      resource = "*.p12";
      effect = "deny";
    }
    {
      action = "read";
      resource = "*.pfx";
      effect = "deny";
    }
    {
      action = "read";
      resource = "id_*";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "sops -d *";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "sops --decrypt *";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "sops decrypt *";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "sops exec-env *";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "sops exec-file *";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "sops output *";
      effect = "deny";
    }
    {
      action = "shell";
      resource = "secret-tool lookup *";
      effect = "deny";
    }
    {
      action = "read";
      resource = "~/.config/shell-secrets/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "~/.config/sops-nix/secrets/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "~/.config/sops/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "//run/user/*/sops-age/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "//run/user/*/secrets.d/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "~/.local/share/keyrings/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "~/.ssh/**";
      effect = "deny";
    }
    {
      action = "read";
      resource = "~/.gnupg/**";
      effect = "deny";
    }
  ];

  secretGuardPaths = [
    "*.env"
    "*.env.*"
    "*.pem"
    "*.key"
    "*.p12"
    "*.pfx"
    "id_*"
    "~/.config/shell-secrets/**"
    "~/.config/sops/**"
    "/run/user/*/sops-age/**"
    "~/.local/share/keyrings/**"
    "~/.ssh/**"
    "~/.gnupg/**"
  ];
  secretGuardReaders = [
    "cat"
    "head"
    "tail"
    "less"
    "more"
    "xxd"
    "od"
    "hexdump"
    "strings"
    "dd"
    "tee"
    "file"
    "stat"
    "grep"
    "rg"
    "awk"
    "sed"
    "cut"
    "column"
    "nl"
    "wc"
    "readelf"
    "objdump"
    "nm"
    "sqlite3"
    "jq"
    "yq"
    "hexyl"
    "bat"
    "pv"
    "gzip"
    "gunzip"
    "bzip2"
    "bunzip2"
    "xz"
    "unxz"
    "zstd"
    "unzstd"
    "lz4"
    "compress"
    "uncompress"
    "zcat"
    "bzcat"
    "xzcat"
    "zstdcat"
    "gpg-connect-agent"
    "ssh-keyscan"
    "ssh-keygen"
  ];
  secretGuardInterpreters = [
    "python"
    "python3"
    "perl"
    "ruby"
    "node"
    "deno"
    "bun"
    "bash"
    "sh"
    "zsh"
    "dash"
    "ksh"
    "sops"
    "sops-nix"
    "age-keygen"
    "ssh"
    "ssh-add"
    "gpg-agent"
    "ssh-agent"
    "secret-tool"
    "kwalletcli"
    "kwallet-query"
    "kwalletd6"
    "kwalletd5"
  ];
  # v1 schema of the same rules — see opencodePermissionV1 in ai-agents.nix.
  opencodeV1Action = a: { shell = "bash"; subagent = "task"; }.${a} or a;
  opencodePermissionV1 = lib.foldl' (acc: r: lib.recursiveUpdate acc {
    ${opencodeV1Action r.action}.${r.resource} = r.effect;
  }) { } opencodePermissions;

  # magpie-community OpenCode 1 provider plugins — same pins as ai-agents.nix.
  magpiePkg = name: version: hash: pkgs.fetchzip {
    url = "https://registry.npmjs.org/@magpie-community/opencode-${name}-auth/-/opencode-${name}-auth-${version}.tgz";
    inherit hash;
  };
  # Upstream main at the merge of #397 (OpenCode 2 support); #396 is in npm
  # 0.1.24 but #397 is unreleased — switch to the npm tarball once a devin
  # release after 0.1.25 exists; see ai-agents.nix for the details.
  devinAuthSrc = pkgs.fetchFromGitHub {
    owner  = "magpie-community";
    repo   = "plugins";
    rev    = "9dbde4573cccbdf3d5e76e3dbb87894b6c3659d3"; # merge of #397
    hash   = "sha256-Qu7S6IOnKWXMKI++7PrlC6FTf5fs5j0/KndLkLXlO7g=";
  };
  devinAuth = "${devinAuthSrc}/packages/devin";
  cursorAuth = magpiePkg "cursor" "0.2.19" "sha256-+JKtCYQ5D0de3+7b6x1tmDEI174F9eFA4oRV9Ce4ynQ=";

  secretGuardSubst = {
    SECRET_PATH_PATTERNS = builtins.toJSON secretGuardPaths;
    SECRET_GUARD_READERS = builtins.toJSON secretGuardReaders;
    SECRET_GUARD_INTERPRETERS = builtins.toJSON secretGuardInterpreters;
  };

  # Same file as desktop — path relative to nix/modules/.
  globalContext = builtins.readFile ../dotfiles/agent-context/global.md;

  # Same writable-settings trick as desktop (home-manager#8654): install -m 644
  # so Claude Code can rewrite at runtime, and carry over Orca's managed hooks
  # (~/.orca/agent-hooks/) — required for the remote Orca server to detect
  # Claude in its terminals.
  claudeCodeSettings = pkgs.writeText "claude-code-settings.json" (
    builtins.toJSON {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      includeCoAuthoredBy = false;
      effortLevel = "medium";
      cleanupPeriodDays = 36500;
      tui = "fullscreen";
      env = {
        FORCE_HYPERLINK = "1";
        CLAUDE_CODE_ENABLE_TODO_TOOLS = "1";
      };
      permissions = {
        allow = [
          "WebFetch"
          "WebSearch"
          "Bash(grep:*)"
          "Bash(rg:*)"
          "Bash(find:*)"
          "Bash(ls:*)"
          "Bash(cat:*)"
          "Bash(head:*)"
          "Bash(tail:*)"
          "Bash(wc:*)"
          "Bash(echo:*)"
          "Bash(du:*)"
          "Bash(df:*)"
          "Bash(ps:*)"
          "Bash(sort:*)"
          "Bash(uniq:*)"
          "Bash(which:*)"
          "Bash(file:*)"
          "Bash(stat:*)"
          "Bash(tree:*)"
          "Bash(xargs ls:*)"
          "Bash(xargs cat:*)"
          "Read(//tmp/**)"
          "Bash(git status:*)"
          "Bash(git log:*)"
          "Bash(git diff:*)"
          "Bash(git show:*)"
          "Bash(git blame:*)"
          "Bash(git ls-tree:*)"
          "Bash(git ls-files:*)"
          "Bash(git branch:*)"
          "Bash(git remote:*)"
          "Bash(git config:*)"
          "Bash(git add:*)"
          "Bash(git commit:*)"
          "Bash(git stash:*)"
          "Bash(git checkout:*)"
          "Bash(git switch:*)"
          "Bash(git restore:*)"
          "Bash(git fetch:*)"
          "Bash(git submodule:*)"
          "Bash(gh pr view:*)"
          "Bash(gh pr diff:*)"
          "Bash(gh pr list:*)"
          "Bash(gh issue view:*)"
          "Bash(gh issue list:*)"
          "Bash(gh run view:*)"
          "Bash(gh run list:*)"
          "Bash(gh search:*)"
          "Bash(nix --version)"
          "Bash(nix eval:*)"
          "Bash(nix search:*)"
          "Bash(nix flake:*)"
          "Bash(nix develop:*)"
          "Bash(nix run:*)"
          "Bash(nix build:*)"
          "Bash(nix profile:*)"
          "Bash(home-manager option:*)"
          "Bash(home-manager switch:*)"
          "Bash(npm install:*)"
          "Bash(npm ci:*)"
          "Bash(npm view:*)"
          "Bash(npm test:*)"
          "Bash(npx tsc:*)"
          "Bash(pnpm install:*)"
          "Bash(pnpm build:*)"
          "Bash(pnpm test:*)"
          "Bash(curl:*)"
          "Bash(ping:*)"
          "Bash(systemctl:*)"
          "Bash(journalctl:*)"
          "Bash(dpkg -l)"
          "Bash(apt list:*)"
          "Bash(docker compose:*)"
          "Bash(docker ps:*)"
          "Bash(podman ps:*)"
          "Bash(podman info:*)"
        ];
        deny = [
          "Read(.env)"
          "Read(.env.*)"
          "Read(!.env.example)"
          "Read(!.env.*.example)"
          "Read(!.env.example.*)"
          "Read(*.pem)"
          "Read(*.key)"
          "Read(*.p12)"
          "Read(*.pfx)"
          "Read(id_*)"
          "Bash(sops -d *)"
          "Bash(sops --decrypt *)"
          "Bash(sops decrypt *)"
          "Bash(sops exec-env *)"
          "Bash(sops exec-file *)"
          "Bash(sops output *)"
          "Bash(secret-tool lookup *)"
          "Read(~/.config/shell-secrets/**)"
          "Read(~/.config/sops-nix/secrets/**)"
          "Read(~/.config/sops/**)"
          "Read(//run/user/*/sops-age/**)"
          "Read(//run/user/*/secrets.d/**)"
          "Read(~/.local/share/keyrings/**)"
          "Read(~/.ssh/**)"
          "Read(~/.gnupg/**)"
        ];
      };
      hooks = {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "python3 ~/.claude/hooks/bash-secret-guard.py";
              }
            ];
          }
        ];
      };
      statusLine = {
        type = "command";
        command = "python3 ~/.claude/statusline/statusline.py";
      };
      # Ponytail plugin (github:DietrichGebert/ponytail) — lazy-senior-dev
      # ruleset + /ponytail* commands, same as desktop ai-agents.nix.
      # Declarative `/plugin marketplace add` + `/plugin install`; its hooks
      # run `node` (nodejs_24 in packages-server.nix).
      extraKnownMarketplaces = {
        ponytail = {
          source = {
            source = "github";
            repo   = "DietrichGebert/ponytail";
          };
        };
      };
      enabledPlugins = {
        "ponytail@ponytail" = true;
      };
    }
  );

  # jq-merged into ~/.config/opencode/cli.json — the file is runtime-mutable
  # (TUI writes back UI-changed settings), so a read-only symlink won't work.
  # Mirror of ai-agents.nix (desktop) — keep the settings identical.
  opencodeCliSettings = builtins.toJSON {
    "$schema" = "https://opencode.ai/v2/cli.json";
    keybinds = {
      leader = "ctrl+x";
      "command.palette.show" = "ctrl+o";
      "session.verbosity.cycle"             = "<leader>v";
      "session.toggle.exploration_grouping" = "<leader>u";
      "session.toggle.thinking"             = "<leader>i";
    };
    session = {
      thinking = "hide";
      grouping = "auto";
      verbosity = "low";
    };
  };

in
{
  # MCP registry — nixos only. freellmapi is wired into OpenCode directly below
  # (OpenCode reads its own mcp.servers, not ~/.config/mcp/mcp.json).
  programs.mcp = {
    enable = true;
    servers = {
      nixos = nixosMcp;
    };
  };

  programs.claude-code = {
    enable = true;
    package = llmAgents.claude-code;
    mcpServers = {
      nixos = nixosMcp;
    };
    context = globalContext;
  };

  home.file.".claude/statusline/statusline.py" = {
    source = ../dotfiles/claude-statusline/statusline.py;
    executable = true;
  };

  programs.codex = {
    enable = true;
    package = llmAgents.codex;
  };

  # Writable settings.json + preserve Orca's managed hooks across hms.
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.claude/settings.json"
    if [ -L "$dest" ]; then
      $DRY_RUN_CMD rm "$dest"
    fi
    tmp="$(mktemp)"
    if [ -s "$dest" ] && ${pkgs.jq}/bin/jq -s '
         (.[0].hooks // {}) as $old
         | .[1]
         | .hooks = reduce ($old | keys[]) as $ev (.hooks // {};
             ($old[$ev] | map(select(any(.hooks[]?; (.command // "") | contains(".orca/agent-hooks/"))))) as $orca
             | if ($orca | length) > 0 then .[$ev] = ((.[$ev] // []) + $orca) else . end)
       ' "$dest" ${claudeCodeSettings} > "$tmp" 2>/dev/null; then
      $DRY_RUN_CMD install -m 644 "$tmp" "$dest"
    else
      $DRY_RUN_CMD install -m 644 ${claudeCodeSettings} "$dest"
    fi
    rm -f "$tmp"
  '';

  home.activation.devinSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/devin/config.json"
    $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp)"
    { [ -s "$dest" ] && cat "$dest" || echo '{}'; } \
      | ${pkgs.jq}/bin/jq '. + { attribution: false,
          hooks: ((.hooks // {}) + {
            PreToolUse: ((.hooks.PreToolUse // []) + [{
              matcher: "Bash",
              hooks: [{ type: "command", command: "python3 ~/.claude/hooks/bash-secret-guard.py" }]
            }])
          }) }' > "$tmp" \
      && $DRY_RUN_CMD install -m 600 "$tmp" "$dest"
    rm -f "$tmp"
  '';

  # OpenCode 2 — same shape as desktop (v2 schema, freellmapi provider + MCP).
  # The binary comes from packages-server.nix wrapped with the sops-sourced
  # FREELLMAPI_API_KEY.
  xdg.configFile."opencode/opencode.json".source = jsonFormat.generate "opencode-config" {
    "$schema" = "https://opencode.ai/config.json";
    # Ponytail plugin — same as desktop ai-agents.nix; v2 fetches the npm
    # package at runtime into ~/.config/opencode/node_modules.
    plugins = [ "@dietrichgebert/ponytail" ];
    # Devin, as in opencode1's config below — served by the fork's v2 plugin
    # (plugins/devin-auth.js) until the port lands upstream (#266).
    model = "devin/swe-2";
    agents.title.model = "devin/swe-1.7-lightning";
    permissions = opencodePermissions;
    providers.freellmapi = {
      name = "FreeLLMAPI";
      env = [ "FREELLMAPI_API_KEY" ];
      package = "@opencode/ai/providers/openai-compatible";
      settings.baseURL = "https://freellmapi.device.example.com/v1";
      models = {
        "auto" = {
          name = "FreeLLMAPI auto";
        };
        "auto:fast" = {
          name = "FreeLLMAPI auto (fast)";
        };
        "auto:smart" = {
          name = "FreeLLMAPI auto (smart)";
        };
      };
    };
    websearch = false;
    mcp.servers.freellmapi = {
      type = "remote";
      url = "https://freellmapi.device.example.com/mcp";
      oauth = false;
      headers.Authorization = "Bearer {env:FREELLMAPI_API_KEY}";
    };
    mcp.servers.nixos = {
      type = "local";
      command = [ nixosMcp.command ] ++ nixosMcp.args;
    };
  };

  # Mirror of ai-agents.nix (desktop) — keep the settings identical.
  home.activation.opencodeCliSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/opencode/cli.json"
    if [ -L "$dest" ]; then $DRY_RUN_CMD rm "$dest"; fi
    $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp)"
    { [ -s "$dest" ] && cat "$dest" || echo '{}'; } \
      | ${pkgs.jq}/bin/jq '. * ${opencodeCliSettings}' > "$tmp" \
      && $DRY_RUN_CMD install -m 600 "$tmp" "$dest"
    rm -f "$tmp"
  '';

  xdg.configFile."opencode/AGENTS.md".text = globalContext;

  # OpenCode 1 (`opencode`/`opencode1`, packages-server.nix) with the magpie
  # Devin/Cursor plugins — same as desktop ai-agents.nix minus the browser MCPs.
  # Isolated under ~/.opencode1 by the wrapper. Sign in with `opencode1 auth login`.
  home.file.".opencode1/config/opencode/opencode.json".source = jsonFormat.generate "opencode1-config" {
    "$schema" = "https://opencode.ai/config.json";
    # Devin, not anthropic/*: see ai-agents.nix (no Anthropic sign-in → big-pickle fallback).
    model = "devin/swe-2";
    small_model = "devin/swe-1.7-lightning";
    permission = opencodePermissionV1;
    provider.freellmapi = {
      name = "FreeLLMAPI";
      npm = "@ai-sdk/openai-compatible";
      options = {
        baseURL = "https://freellmapi.device.example.com/v1";
        apiKey = "{env:FREELLMAPI_API_KEY}";
      };
      models = {
        "auto" = {
          name = "FreeLLMAPI auto";
        };
        "auto:fast" = {
          name = "FreeLLMAPI auto (fast)";
        };
        "auto:smart" = {
          name = "FreeLLMAPI auto (smart)";
        };
      };
    };
    mcp.freellmapi = {
      type = "remote";
      url = "https://freellmapi.device.example.com/mcp";
      oauth = false;
      headers.Authorization = "Bearer {env:FREELLMAPI_API_KEY}";
    };
    mcp.nixos = {
      type = "local";
      command = [ nixosMcp.command ] ++ nixosMcp.args;
    };
  };
  # opencode2 reads plugin files from ~/.config/opencode/plugins/; the fork
  # has the v2 default export the upstream tarball lacks (#266).
  xdg.configFile."opencode/plugins/devin-auth.js".text =
    ''export { default } from "${devinAuth}/index.mjs"'';
  home.file.".opencode1/config/opencode/plugins/devin-auth.js".text =
    ''export { DevinAuthPlugin } from "${devinAuth}/index.mjs"'';
  home.file.".opencode1/config/opencode/plugins/cursor-auth.js".text =
    ''export { CursorAuthPlugin } from "${cursorAuth}/index.mjs"'';
  home.file.".opencode1/config/opencode/AGENTS.md".text = globalContext;

  # Hook scripts — same sources as desktop.
  home.file.".claude/hooks/bash-secret-guard.py" = {
    source = pkgs.replaceVars ../dotfiles/claude-hooks/bash-secret-guard.py secretGuardSubst;
    executable = true;
  };

  home.file.".config/opencode/plugins/secret-guard.js".source =
    pkgs.replaceVars ../dotfiles/opencode-plugins/secret-guard.js secretGuardSubst;
  home.file.".opencode1/config/opencode/plugins/secret-guard.js".source =
    pkgs.replaceVars ../dotfiles/opencode-plugins/secret-guard-v1.js secretGuardSubst;

  home.file.".claude/direnv-env.sh".text = ''
    if command -v direnv >/dev/null 2>&1; then
      export DIRENV_LOG_FORMAT=""
      eval "$(direnv export bash 2>/dev/null)"
    fi
  '';

  home.sessionVariables.CLAUDE_ENV_FILE = "$HOME/.claude/direnv-env.sh";
}
