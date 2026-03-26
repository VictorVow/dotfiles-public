## Meta

This file is maintained by `update.sh` and updated during system updates.

**Structure:**
- **Meta** (this section): Documents the structure and formatting of this file.
- **News**: Raw plain-text output from `home-manager news`, captured silently.

**Formatting rules for the News section:**
- Content is the verbatim output of `home-manager news` — do not hand-edit it.
- Each news entry starts with a `#` heading (package name and version range).
- Entries are separated by blank lines.

**Update behaviour:** `update.sh` compares new news output against the stored
News section and prompts before overwriting (Y/n, default Y). Skipped in
non-interactive (cron) sessions.

Last updated: 2026-03-26 11:14:08

## News

warning: Git tree '/home/boss/Documents/ESSENTIALS/installs' has uncommitted changes
* 2026-03-24 15:51:30 [read]

  A new module is available: `qt.kvantum`.
  
  Enable it with `qt.kvantum.enable = true;`.
  
  It can install Kvantum theme packages into
  {file}`$XDG_CONFIG_HOME/Kvantum/` and generate
  {file}`$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig`
  from `qt.kvantum.settings`.
  


* 2026-03-20 04:51:15 [read]

  A new module is available: 'programs.nom'.
  
  Nom is a terminal-based, rss feed reader that looks like
  the markdown reader glow and supports defining different
  openers for different url regex patterns.
  


* 2026-03-15 20:42:27 [read]

  programs.smug.projects.<name>.session is a new optional setting that
  can be used to specify a different session name from the project name.
  


* 2026-03-12 13:04:00 [read]

  The ruby provider is now disabled by default since the overwhelming majority of users do not use it.
  Set `programs.neovim.withRuby = true;` to restore the previous behavior.
  


* 2026-02-24 18:17:29 [read]

  The options 'xsession.windowManager.i3.config.gaps.smartGaps' and
  'wayland.windowManager.sway.config.gaps.smartGaps' now expects either "on",
  "off" (default) or "inverse_outer".
  


* 2026-02-23 05:21:28 [read]

  A new module is available: 'programs.w3m'.
  
  W3m is a commandline web browser, manpage viewer, and pager.
  


* 2026-02-18 17:20:43 [read]

  A new module is available: 'programs.rizin'.
  
  Rizin is a free and open-source reverse engineering framework
  that delivers a comprehensive binary analysis experience.
  It focuses on usability, stability, and functional features,
  striving to create a welcoming environment for developers and users.
  


* 2026-02-17 14:42:25 [read]

  
  A new module is available: 'programs.mistral-vibe'.
  
  mistral-vibe is Mistral's open-source CLI coding assistant.
  


* 2026-02-13 11:21:10 [read]

  
  A new module is available: 'programs.tirith'.
  
  Tirith is a shell security monitor that helps protect against
  malicious commands by analyzing shell inputs before execution.
  


* 2026-02-12 05:16:46 [read]

  The `services.flameshot` module now supports Darwin by generating a
  launchd agent in addition to the existing Linux systemd service.
  


* 2026-02-08 13:59:14 [read]

  A new module is available: `programs.lazyworktree`
  
  LazyWorktree is a TUI for Git worktrees. It provides a keyboard-driven
  workflow for creating, inspecting, and navigating worktrees within a repository.
  


* 2026-01-27 20:02:41 [read]

  A new module is available: 'programs.prismlauncher'.
  
  An open-source Minecraft launcher that can manage multiple instances,
  accounts, and mods. Focused on user freedom and free redistributability.
  


* 2026-01-25 18:00:28 [read]

  The neovim module now exposes programs.neovim.extraLuaPackages via init.lua instead of wrapper arguments.
  This makes for a better out of the box experience, closer to what users can expect on other distributions, i.e., you
  can now run any neovim derivatives (neovide, neovim-qt etc) without wrapping.
  
  If you used home-manager only to install plugins, the newly generated init.lua might conflict with yours.
  You can ignore the generated init.lua with
  `xdg.configFile."nvim/init.lua".enable = false` but `extraLuaPackages` will become ineffective.
  You can still refer to its generated content via:
      xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;
    and in your manual init.lua `require'hm-generated'`
  
  For more details, see:
  - https://github.com/nix-community/home-manager/pull/8586
  - https://github.com/nix-community/home-manager/pull/8606 and its linked comments for more details/solutions.
  


* 2026-01-19 05:36:20 [read]

  Chrome now has a `plasmaSupport` flag.
  
  If you use KDE Plasma, set:
  
  ```
  programs.google-chrome.plasmaSupport = true`
  home.sessionVariables = [
    QT_QPA_PLATFORMTHEME = "kde";
  ];
  ```
  
  This enables the "Use QT" theme in **Settings > Appearance**, which makes
  Chrome match your Plasma theme.
  


* 2026-01-19 03:12:38 [read]

  A new module `programs.pyradio` is available.
  
  A curses based internet radio player.
  


* 2026-01-19 01:17:02 [read]

  The neovim module now symlinks its plugins into xdg.dataFile."nvim/site/pack/hm" ( ~/.local/share/nvim) instead of modifying the runtimepath via wrapper arguments.
  


* 2026-01-18 14:07:27 [read]

  A new 'programs.vscode.argvSettings' option is available to configure VS
  Code this creates the `argv.json` file.
  


* 2026-01-14 17:05:44 [read]

  A new module is available: `programs.aphorme`
  
  A program launcher for window managers, written in Rust.
  


* 2026-01-14 16:52:53 [read]

  A new module is available: `programs.aperture`
  
  Aperture is a HTTP 402 reverse proxy that supports proxying requests for
  gRPC (HTTP/2) and REST (HTTP/1 and HTTP/2) backends using the L402 Protocol Standard.
  


* 2026-01-14 14:54:50 [read]

  There is a new option, 'home-manager.startAsUserService', which
  causes home-manager to set up each user's personal environment on
  demand when they log in, instead of doing all the setup work
  proactively during system boot.  Using this mode makes
  home-manager compatible with pam_mount and other situations where
  users' home directories are not available until they log in.
  


* 2026-01-11 16:02:12 [read]

  The starship module has a new option, programs.starship.presets, which
  allows for merging user configuration with Starship's bundled presets.
  


* 2026-01-11 04:00:11 [read]

  A new option is available: `systemd.user.packages`.
  
  This option is the Home Manager equivalent of NixOS’s `systemd.packages`
  option and provides a way to specify packages providing systemd user units.
  
  This option is similar to `dbus.packages`.
  


* 2026-01-10 18:52:15 [read]

  A new module is available: `services.proton-pass-agent`
  
  This module allows you to use Proton Pass as a SSH agent, enabling secure
  storage and management of SSH keys through your Proton Pass vault.
  
  The service integrates with the usual shells (bash, zsh, fish, nushell) and
  provides options to:
  - Specify a vault or share ID to pull keys from
  - Configure automatic key refresh intervals
  - Enable automatic creation of new SSH key items when added via ssh-add
  
  The agent runs as a systemd user service on Linux and as a launchd agent
  on macOS, automatically setting the SSH_AUTH_SOCK environment variable.
  


* 2026-01-05 11:57:57 [read]

  A new module is available: 'programs.workstyle'.
  
  Workstyle dynamically renames Sway/i3/Hyprland workspaces to indicate
  which programs are running in each one. For example, with a font icon.
  


* 2025-12-06 10:05:43 [read]

  A new module is available: `programs.ty`
  
  It allows to manage the configuration and package
  of the Python language server `ty` by Astral.
  


* 2025-12-06 10:03:01 [read]

  A new module is available: `programs.npm`
  
  It allows you manage your npm user configuration (`.npmrc`)
  and install a specific version of the package.
  


* 2025-12-05 01:50:03 [read]

  A new module is available: `programs.hyprlauncher`
  
  Hyprlauncher is a multipurpose and versatile launcher/picker
  for hyprland. It’s fast, simple, and provides various modules.
  


* 2025-12-04 19:34:38 [read]

  A new module is available: `programs.screen`
  
  GNU Screen is a terminal multiplexer, a software application that can
  be used to multiplex several virtual consoles, allowing a user to access
  multiple separate login sessions inside a single terminal window, or detach
  and reattach sessions from a terminal.
  


* 2025-12-03 13:14:53 [read]

  A new module is available: `programs.calibre`
  
  Calibre is a powerful and easy to use e-book manager. Users say it’s outstanding
  and a must-have. It’ll allow you to do nearly everything and it takes things a
  step beyond normal e-book software. It’s also completely free and open source
  and great for both casual users and computer experts.
  


* 2025-11-29 23:04:38 [read]

  A new module is available: 'programs.parallel'.
  


* 2025-11-26 10:55:28 [read]

  The option 'gtk.theme' does not apply to GTK 4 automatically anymore for new
  installations (with `home.stateVersion` >= "26.05"). Using a custom theme is
  not officially supported by GTK 4, and implemented by home-manager using a
  workaround that may cause issues in some cases. If you still want to use a GTK
  4 theme, you need to explicitly set 'gtk.gtk4.theme'.
  


* 2025-11-26 05:33:49 [read]

  A new module is available: 'programs.cargo'.
  
  cargo is the build system and package manager of Rust.
  


* 2025-11-25 02:56:51 [read]

  A new option `programs.claude-code.skills` is now available.
  
  It allows you to extend claude-code's capabilities by defining agent skills.
  


* 2025-11-15 08:54:20 [read]

  A new module is available: 'programs.bluetuith'.
  
  bluetuith is a TUI-based Bluetooth connection manager, which can interact
  with Bluetooth adapters and devices. It aims to be a replacement to most
  Bluetooth managers, like blueman.
  


* 2025-11-08 20:50:07 [read]

  A new module is available: 'programs.retroarch'.
  
  RetroArch is a frontend for emulators, game engines, and media players.
  Among other things, it enables you to run classic games on a wide
  range of computers and consoles through its slick graphical interface.
  


* 2025-11-06 11:50:53 [read]

  A new module is available: 'services.tomat'.
  
  tomat is a Pomodoro timer for status bars and the command line. It is easily configurable and support both desktop and sound notifications.
  


* 2025-11-04 15:44:03 [read]

  The 'services.podman' module now supports Darwin (macOS) with declarative
  machine management.
  
  On Darwin, podman requires running containers inside a virtual machine.
  The new configuration options allow you to declaratively manage podman
  machines with automatic creation, configuration, and startup.
  
  By default, a machine named 'podman-machine-default' will be created
  automatically. You can customize machines or disable the default with:
  
    services.podman.useDefaultMachine = false;
    services.podman.machines = {
      "my-machine" = {
        cpus = 4;
        memory = 8192;
        diskSize = 100;
        autoStart = true;
      };
    };
  
  The module includes a launchd-based watchdog service that automatically
  starts configured machines on login and keeps them running.
  


* 2025-11-04 13:00:00 [read]

  A new module is available: 'programs.opkssh'.
  
  opkssh is a tool which enables ssh to be used with OpenID Connect allowing SSH access to be managed via identities instead of long-lived SSH keys. It does not replace SSH, but instead generates SSH public keys containing PK Tokens and configures sshd to verify them. These PK Tokens contain standard OpenID Connect ID Tokens.
  
  This protocol builds on the OpenPubkey which adds user public keys to OpenID Connect without breaking compatibility with existing OpenID Provider.
  


* 2025-11-04 04:40:09 [read]

  A new program is available: 'programs.discord'.
  
  Discord is an instant messaging platform with an Electron-based client.
  
  The module provides:
  - Support for toggling Discord's update checks, as they prevent older
    versions of the app from launching.
  - Support for enabling Chrome's web devtools inside Discord.
  
  See the module options for more details on configuration.
  


* 2025-11-04 02:33:15 [read]

  A new program is available: 'programs.vicinae'.
  
  Vicinae is a modern application launcher daemon for Linux with support for
  extensions, custom themes, and layer shell integration.
  
  The module provides:
  - Systemd service integration with automatic start support
  - Extension management with helpers for Vicinae and Raycast extensions
  - Theme configuration support
  - Declarative settings via 'programs.vicinae.settings'
  - Layer shell integration for Wayland compositors
  
  See the module options for more details on configuration.
  


* 2025-11-03 10:18:15 [read]

  A new module 'programs.mcp' is now available for managing Model
  Context Protocol (MCP) server configurations.
  
  The 'programs.mcp.servers' option allows you to define MCP servers
  in a central location. These configurations can be automatically
  integrated into applications that support MCP.
  
  Two modules now support MCP integration:
  
  - 'programs.opencode.enableMcpIntegration': Integrates MCP servers
    into OpenCode's configuration.
  
  - 'programs.vscode.profiles.<name>.enableMcpIntegration': Integrates
    MCP servers into VSCode profiles.
  
  When integration is enabled, servers from 'programs.mcp.servers' are
  merged with application-specific MCP settings, with the latter taking
  precedence. This allows you to define MCP servers once and reuse them
  across multiple applications.
  


* 2025-10-31 12:00:00 [read]

  services.local-ai: new module
  
  Added LocalAI, a free, Open Source OpenAI alternative.
  


* 2025-10-30 17:25:46 [read]

  A new option 'backupCommand' is now available for Home Manager activation.
  
  This option allows you to specify a custom command to run on existing files
  during activation. If set, it takes precedence over 'backupFileExtension',
  but can work together with it by referencing the '$HOME_MANAGER_BACKUP_EXT'
  environment variable in your command.
  
  This enables advanced backup workflows, such as moving files to trash or
  archiving with custom tools, before managing them with Home Manager.
  
  The option is available in standalone, NixOS, and nix-darwin configurations.
  


* 2025-10-26 21:07:01 [read]

  A new module is available: `programs.zapzap`
  
  ZapZap brings the WhatsApp experience on Linux closer to that of a native application.
  Since Meta does not provide a public API for third-party applications, ZapZap is developed
  as a Progressive Web Application (PWA), built with PyQt6 + PyQt6-WebEngine.
  


* 2025-10-26 07:36:05 [read]

  A new module is available: `programs.kraftkit`.
  
  kraftkit is a CLI tool for building custom, minimal, immutable lightweight
  unikernel virtual machines based on Unikraft.
  


* 2025-10-26 07:19:48 [read]

  A new module is available: `targets.genericLinux.gpu`
  
  This module provides integration of GPU drivers for non-NixOS systems. It is a
  simpler alternative to the existing `targets.genericLinux.nixGL` module. See the
  Home Manager user manual for more information.
  


* 2025-10-25 14:45:39 [read]

  The home-manager auto-upgrade service now supports updating Nix flakes.
  
  Enable this by setting `services.home-manager.autoUpgrade.useFlake = true;`.
  
  The flake directory can be configured with `services.home-manager.autoUpgrade.flakeDir`,
  which defaults to the configured XDG config home (typically `~/.config/home-manager`).
  


* 2025-10-17 00:46:07 [read]

  A new module is available: 'services.wl-clip-persist'.
  
  This module provides clipboard persistence for Wayland compositors,
  ensuring clipboard contents remain available after the source application
  closes. The service runs as a systemd user service and integrates with
  your Wayland session target.
  


* 2025-10-14 23:44:58 [read]

  A new module is available: `services.colima`
  
  Colima is a tool for orchestrating container runtimes under a linux VM.
  


* 2025-10-11 20:56:35 [read]

  A new module is available: `programs.anvil-editor`
  
  Anvil is a graphical, multi-pane tiling editor that makes bold use
  of the mouse and integrates closely with the shell. It supports syntax
  highlighting, multiple cursors and selections, remote file editing, and
  contains a powerful text manipulation language.
  


* 2025-10-11 14:06:00 [read]

  A new service is available: 'services.autotiling'.
  autotiling is a script for Sway and i3 to automatically switch the horizontal / vertical window split orientation.
  


* 2025-10-11 00:06:01 [read]

  A new option is available: `home-manager.minimal`
  
  By default, Home Manager imports all modules, which leads to increased
  evaluation time. Some users may wish to only import the modules they
  actually use. When the new option is enabled, Home Manager will only
  import the basic set of modules it requires to function. Other modules
  will have to be enabled manually, like this:
  
  ```nix
    imports = [
      "${modulesPath}/programs/fzf.nix"
    ];
  ```
  
  This entrypoint is only recommended for advanced users, who are
  comfortable maintaining a personal list of modules to import.
  


* 2025-10-10 18:56:49 [read]

  A new module is available: `programs.anup`
  
  Anup is a TUI application to play and manage anime with AniList for Linux systems.
  


* 2025-10-10 18:24:32 [read]

  A new module is available: `programs.anime-downloader`
  
  Anime-Downloader is a simple but powerful anime downloader and streamer.
  


* 2025-10-09 19:34:56 [read]

  A new module is available: `programs.andcli`
  
  Andcli lets you work with 2FA tokens directly in your shell,
  using encrypted backups exported out of your favourite 2FA apps.
  All the data is held in memory only and will never leave your machine.
  


* 2025-10-09 19:14:29 [read]

  A new module is available: `programs.amp`
  
  Amp is a complete text editor for your terminal.
  Heavily inspired by Vi/Vim. Amp aims to take the core interaction model
  of Vim, simplify it, and bundle in the essential features required for
  a modern text editor.
  


* 2025-10-07 12:39:32 [read]

  A new module is available: `programs.amoco`
  
  Amoco is a python package dedicated to symbolic analysis of binaries.
  


* 2025-10-06 23:28:22 [read]

  A new module is available: `programs.amfora`
  
  Amfora aims to be the best looking Gemini client with the most features...
  all in the terminal. It does not support Gopher or other non-Web protocols
  - check out Bombadillo for that.
  


* 2025-10-05 18:18:28 [read]

  A new module is available: `programs.amber`
  
  Amber is a code search and replace tool written in Rust.
  This tool is inspired by ack, ag, and other grep-like tools.
  


* 2025-10-05 17:55:44 [read]

  A new module is available: `programs.am2rlauncher`
  
  AM2RLauncher is a front-end application that simplifies installing the
  latest AM2R-Community-Updates, creating APKs for Android use, as well as
  Mods for AM2R. It supports Windows (x86/x64) as well as Linux (x64).
  


* 2025-10-03 02:36:31 [read]

  A new module is available: `programs.asciinema`
  
  `asciinema` is a tool for recording, replaying, publishing, and live
  streaming terminal session.
  
  This module enables declaring configuration via `.settings`, check the
  official documentation for details;
  https://docs.asciinema.org/manual/cli/quick-start/
  


* 2025-10-02 15:54:47 [read]

  A new module is available: `programs.alistral`
  
  Alistral is a collection of CLI based tools for Listenbrainz.
  


* 2025-09-29 19:23:12 [read]

  A new module is available: `programs.aliae`
  
  Aliae is a cross shell and platform alias management tool.
  


* 2025-09-29 17:01:34 [read]

  A new module is available: `programs.algia`
  
  Algia is a CLI application for nostr, written in Go.
  


* 2025-09-28 22:34:55 [read]

  A new module is available: `programs.intelli-shell`
  
  IntelliShell is a command-line tool that acts as a smart bookmark manager.
  It helps you find, organize, and reuse complex shell commands without ever
  leaving your terminal.
  


* 2025-09-28 06:57:30 [read]

  A new module is available: 'programs.radio-active'
  
  `radio-active` is a TUI which enables playing of radio station streams.
  
  This module allows for defining configuration file as well as favorites
  list via Nix attribute sets.
  


* 2025-09-26 14:46:57 [read]

  A new module is available: `programs.airlift`
  
  Airlift is a Command Line Interface (CLI) tool designed to provide
  a local development environment for Apache Airflow with a simple but
  flexible interface. It is built on top of the official Airflow Helm Chart.
  


* 2025-09-26 14:20:32 [read]

  A new module is available: `programs.aider-chat`
  
  Aider lets you pair program with LLMs to start a new project
  or build on your existing codebase. It works with most popular
  programming languages: Python, Javascript, Rust, Ruby, Go, C++,
  PHP, HTML, CSS, and dozens more.
  


* 2025-09-24 19:33:28 [read]

  A new module is available: `programs.aiac`
  
  aiac is a library and command line tool to generate IaC (Infrastructure as Code)
  templates, configurations, utilities, queries and more via LLM providers such as
  OpenAI, Amazon Bedrock and Ollama.
  


* 2025-09-23 13:42:39 [read]

  A new module is available: `programs.ahoviewer`
  
  Ahoviewer is a GTK image viewer, manga reader, and booru browser.
  


* 2025-09-20 18:04:36 [read]

  A new module is available: `programs.fabric-ai`
  
  Fabric is an open-source framework for augmenting humans using AI.
  It provides a modular system for solving specific problems using a
  crowdsourced set of AI prompts that can be used anywhere.
  


* 2025-09-20 12:29:51 [read]

  A new module is available: `programs.animdl`
  
  A highly efficient, fast, powerful and light-weight
  anime downloader and streamer for your favorite anime.
  


* 2025-09-19 14:24:17 [read]

  A new module is available: `programs.wleave`
  
  A Rust/GTK4 port of `programs.wlogout` with improvements.
  


* 2025-09-18 23:12:11 [read]

  Nix remote builders can be declared by setting `nix.distributedBuilds = true`
  and populating `nix.buildMachines`.
  


* 2025-09-18 17:05:15 [read]

  A new module is available: `programs.acd-cli`
  
  acd_cli provides a command line interface to Amazon Drive and
  allows Unix users to mount their drive using FUSE for read and
  (sequential) write access. It is currently in beta stage.
  


* 2025-09-18 16:25:16 [read]

  A new module is available: `programs.abaddon`
  
  An alternative Discord client with voice support made with C++ and GTK 3
  


* 2025-09-18 14:46:18 [read]

  A new module is available: `programs.retext`
  
  ReText is a simple but powerful editor for markup languages. It is based on
  Markups module which supports Markdown, reStructuredText, Textile and
  AsciiDoc. One can also add support for custom markups using Python modules.
  


* 2025-09-18 00:13:27 [read]

  A new module is available: `programs.formiko`
  
  Formiko is reStructuredText and MarkDown editor and live previewer.
  It is written in Python with Gtk3, GtkSourceView and Webkit2.
  Use Docutils and MarkDown to reStructuredText covertor.
  


* 2025-09-17 05:03:26 [read]

  A new service is available: 'services.tailscale-systray'.
  


* 2025-09-15 22:14:27 [read]

  A new module is available: `programs.nvchecker`.
  
  `nvchecker` checks if a new version of some software was released.
  


* 2025-09-13 16:36:15 [read]

  A new module is available: `programs.cudatext`
  
  CudaText is a cross-platform text editor, written in Object Pascal.
  It is open source project and can be used free of charge, even for business.
  It starts quite fast: ~0.3 sec with ~30 plugins, on Linux on CPU Intel Core
  i3 3GHz. It is extensible by Python add-ons: plugins, linters, code tree parsers,
  external tools. Syntax parser is feature-rich, from EControl engine.
  


* 2025-09-12 15:02:45 [read]

  A new module is available: 'programs.jjui'
  
  jjui is a terminal user interface for jujutsu version control system.
  


* 2025-09-08 18:49:30 [read]

  A new module is available: 'programs.radicle'.
  A new service is available: 'services.radicle.node'.
  
  Radicle is a distributed code forge built on Git.
  Since it is possible to interact with Radicle storage without running the service, two modules were introduced.
  


* 2025-09-06 17:04:11 [read]

  A new module is available: 'programs.pianobar'.
  
  `pianobar` is a console front-end for Pandora.com and provides options to
  extend with third-party applications or scripts.  This module enables
  declarative configuration of all documented options.
  


* 2025-09-03 21:44:34 [read]

  A new module is available: `programs.vivid`
  
  Vivid is a generator for the LS_COLORS environment variable
  that controls the colorized output of ls, tree, fd, bfs, dust
  and many other tools.
  


* 2025-09-02 13:29:23 [read]

  A new module is available: `programs.swappy`
  
  Swappy is a Wayland native snapshot and editor tool,
  inspired by Snappy on macOS. Works great with grim,
  slurp and sway. But can easily work with other screen
  copy tools that can output a final image to stdout.
  


* 2025-08-30 16:07:19 [read]

  A new module is available: 'services.shpool'.
  
  shpool is a service that enables session persistence by allowing the creation of named shell sessions owned by shpool so that the session is not lost if the connection drops.
  
  Read about it at https://github.com/shell-pool/shpool
  


* 2025-08-18 17:37:24 [read]

  A new module is available: 'programs.satty'
  
  Satty is a screenshot annotation tool, inspired by Swappy and Flameshot.
  It can easily integrate with your wlroots based screenshot tool and
  comes with a simple and functional UI for post-processing your screenshots.
  


* 2025-08-16 01:35:44 [read]

  A new module is available: 'programs.hyprshot'
  
  Hyprshot is an utility to easily take screenshot in Hyprland using your mouse.
  It allows taking screenshots of windows, regions and monitors which are saved
  to a folder of your choosing and copied to your clipboard.
  


* 2025-08-15 20:51:02 [read]

  A new module is available: 'programs.claude-code'.
  
  Claude Code is Anthropic's official CLI for Claude, providing an
  interactive command-line interface for AI-assisted development.
  
  The module supports:
  - Configuration through 'programs.claude-code.settings'
  - Custom agents via 'programs.claude-code.agents'
  - Custom commands via 'programs.claude-code.commands'
  - MCP (Model Context Protocol) servers via 'programs.claude-code.mcpServers'
  - Package installation control via 'programs.claude-code.package'
  


* 2025-08-13 21:34:57 [read]

  A new module is available: 'services.protonmail-bridge'.
  
  ProtonMail Bridge is a desktop application that runs in the background,
  encrypting and decrypting messages as they enter and leave your computer.
  It lets you add your ProtonMail account to your favorite email client via
  IMAP/SMTP by creating a local email server on your computer.
  


* 2025-08-11 04:23:58 [read]

  A new service is available: 'services.walker'.
  
  Walker is a fast, customizable application launcher. It provides
  a themeable interface for launching applications, running commands, and more.
  


* 2025-08-10 16:03:30 [read]

  A new module is available: 'programs.jrnl'.
  
  jrnl is a command-line journaling application that stores your journal
  entries in plain text files with optional encryption. This module allows
  configuring jrnl settings including journals, encryption, and output formats.
  


* 2025-08-09 22:11:00 [read]

  A new service is available: 'services.pizauth'.
  
  Pizauth is a simple program for requesting, showing, and refreshing OAuth2 access tokens.
  Pizauth is formed of two components: a persistent server which interacts with the user to request tokens, and refreshes them as necessary;
  and a command-line interface which can be used by programs such as fdm and msmtp to authenticate with OAuth2.
  


* 2025-08-08 00:39:04 [read]

  A new module is available: 'programs.sheldon'.
  
  Sheldon is a fast shell plugin manager that supports Bash, Zsh, and Fish.
  It allows you to manage shell plugins efficiently with configuration
  through a simple TOML file.
  


* 2025-08-07 13:39:36 [read]

  A new module is available: 'programs.mullvad-vpn'.
  
  The Mullvad VPN module allows configuration of the Mullvad VPN client,
  including account settings, connection preferences, and advanced options
  for secure and private internet browsing.
  


* 2025-08-06 04:18:50 [read]

  A new service is available: 'services.rescrobbled'.
  
  Rescrobbled is a music scrobbler daemon. It detects active media players
  running on D-Bus using MPRIS automatically updates "now playing" status, and
  scrobbles songs to Last.fm or ListenBrainz-compatible services as they play.
  


* 2025-08-06 00:14:30 [read]

  A new module is available: 'programs.sherlock'.
  
  The sherlock module allows configuring Sherlock launcher, a fast and
  lightweight application launcher for Linux. You can customize settings,
  define custom aliases for web searches, configure fallback launchers,
  specify applications to ignore, and apply custom CSS styling.
  


* 2025-08-05 19:17:36 [read]

  The 'fontconfig' module now supports font rendering configuration.
  
  New options have been added to control font appearance:
  - 'fontconfig.antialiasing' - Enable/disable font antialiasing
  - 'fontconfig.hinting' - Set hinting mode (none, slight, medium, full)
  - 'fontconfig.subpixelRendering' - Configure sub-pixel rendering (none, rgb, bgr, etc.)
  


* 2025-08-05 19:13:33 [read]

  A new module is available: 'programs.grep'.
  
  The grep module allows configuring GREP_COLORS environment variable to
  customize the colors used in grep output highlighting.
  


* 2025-08-05 19:13:23 [read]

  A new module is available: 'programs.gcc'.
  
  The gcc module allows configuring GCC_COLORS environment variable to
  customize the colors used in GCC diagnostic output.
  


* 2025-08-05 19:13:10 [read]

  A new module is available: 'programs.nix-search-tv'.
  
  The nix-search-tv program provides a terminal UI for searching Nix packages,
  offering a fast and interactive way to browse and find packages in the Nix
  ecosystem.
  


* 2025-08-01 14:53:46 [read]

  The 'programs.tmux' module has improved prefix key configuration.
  
  Custom prefix key settings now properly register and function correctly.
  If you previously had issues with custom prefix keys not working,
  they should now function as expected.
  


* 2025-07-29 17:20:22 [read]

  Package options have been added to 34 modules across Home Manager.
  
  Many program and service modules now include a 'package' option, allowing
  you to specify custom package versions or variants instead of using the
  default packages. This improves flexibility for users with specific
  package requirements.
  


* 2025-07-25 17:54:38 [read]

  A new module is available: 'xdg.terminal-exec'.
  
  This module allows configuring the default terminal emulator for XDG
  applications, ported from NixOS to Home Manager.
  


* 2025-07-23 18:13:14 [read]

  A new module is available: 'programs.yofi'.
  
  Yofi is a minimalistic menu/launcher for Wayland compositors. It provides
  a fast and lightweight application launcher with search functionality
  and customizable appearance.
  


* 2025-07-23 15:42:37 [read]

  A new module is available: 'programs.yarn'.
  
  This module provides configuration options for the Yarn package manager,
  allowing you to configure Yarn settings, authentication, and other
  preferences through your Home Manager configuration.
  


* 2025-07-18 00:31:15 [read]

  A new service is available: 'services.ssh-tpm-agent'.
  
  The ssh-tpm-agent service provides SSH authentication using TPM (Trusted
  Platform Module) for enhanced security with hardware-backed keys.
  


* 2025-07-17 19:21:31 [read]

  A new module is available: 'programs.radio-cli'.
  
  This module provides configuration for the radio-cli command-line radio
  player, allowing you to listen to internet radio stations directly from
  your terminal with configurable settings and station presets.
  


* 2025-07-13 22:51:03 [read]

  A new module is available: 'programs.gurk-rs'.
  
  gurk-rs is a Signal messenger client for the terminal written in Rust.
  It provides a text-based interface for secure messaging with features
  like group chats, media sharing, and contact management.
  


* 2025-07-10 20:36:53 [read]

  A new module is available: 'programs.docker-cli'.
  
  The Docker CLI module provides configuration for the Docker command-line
  interface, including aliases, completion settings, and credential helpers
  for managing Docker containers and images.
  


* 2025-07-10 19:23:15 [read]

  A new service is available: 'services.hyprshell'.
  
  Hyprshell is a modern GTK4-based window switcher and application launcher
  designed specifically for Hyprland. It provides a clean interface for
  switching between windows and launching applications.
  


* 2025-07-08 15:56:50 [read]

  A new module is available: 'programs.firefoxpwa'.
  
  Firefox PWA (Progressive Web Apps) allows installing and managing web
  applications as native desktop applications. This module provides
  configuration for the Firefox PWA runtime and site management.
  


* 2025-07-08 14:52:03 [read]

  A new module is available: 'programs.twitch-tui'.
  
  twitch-tui is a terminal user interface for Twitch that allows browsing
  streams, following channels, and interacting with Twitch chat directly
  from the command line.
  


* 2025-07-08 14:51:45 [read]

  A new module is available: 'programs.tray-tui'.
  
  tray-tui is a terminal-based system tray that displays system tray icons
  in a text user interface. It provides a way to access system tray
  functionality directly from the terminal.
  


* 2025-06-24 03:44:23 [read]

  A new module is available: 'programs.quickshell'.
  


* 2025-06-15 02:49:02 [read]

  A new module is available: 'programs.anki'.
  
  Anki is a spaced repetition flashcard program. 
  


* 2025-06-13 16:14:02 [read]

  A new module is available: 'programs.kubeswitch'.
  
  The kubectx for operators.
  kubeswitch (lazy: switch) is the single pane of glass for all of your kubeconfig files.
  


* 2025-06-12 17:07:18 [read]

  A new module is available: 'programs.ashell'.
  


* 2025-06-10 03:33:16 [read]

  A new module is available: 'programs.codex'.
  
  This module provides configuration for OpenAI Codex, an AI system that
  translates natural language to code. It powers GitHub Copilot and can
  be used for code generation and completion tasks.
  


* 2025-06-09 15:12:11 [read]

  A new module is available: 'programs.niriswitcher'.
  
  niriswitcher is an application switcher for niri, with support for
  workspaces and automatic light and dark mode.
  


* 2025-06-09 14:25:11 [read]

  A new module is available: 'programs.mc'.
  
  This module provides configuration for Midnight Commander (mc), a
  powerful console-based file manager with dual-pane interface, allowing
  you to customize settings, key bindings, and appearance.
  


* 2025-06-08 16:27:00 [read]

  A new module is available: 'programs.nyxt'.
  
  This module provides configuration for Nyxt, a keyboard-driven web
  browser designed for power users, with extensive customization options
  and a Lisp-based configuration system.
  


* 2025-06-08 04:51:28 [read]

  A new module is available: 'programs.lazysql'.
  
  This module provides configuration for LazySql, a terminal-based SQL
  client with an intuitive interface for database management and query
  execution across multiple database engines.
  


* 2025-06-04 18:35:39 [read]

  A new module is available: 'programs.aichat'.
  
  This module provides configuration for aichat, an AI-powered command-line
  chat client that supports multiple AI models and allows for easy
  interaction with various AI services from your terminal.
  


* 2025-05-29 18:33:51 [read]

  A new module is available: 'programs.hwatch'.
  


* 2025-05-29 03:30:10 [read]

  A new module is available: 'programs.meli'.
  
  This module provides configuration for meli, a fast and modern terminal
  email client written in Rust, offering an alternative interface for
  managing your email workflows.
  


* 2025-05-24 23:55:23 [read]

  A new module is available: 'programs.obsidian'.
  
  This module provides configuration for Obsidian, a powerful knowledge
  management and note-taking application that uses linked markdown files
  to help you build a personal knowledge graph.
  


* 2025-05-24 18:18:40 [read]

  A new module is available: `services.wayvnc`
  
  wayvnc is a VNC server for wlroots based Wayland compositors.
  


* 2025-05-16 20:29:26 [read]

  A new module is available: 'programs.ptyxis'.
  
  This module provides configuration for Ptyxis, a modern GNOME terminal
  emulator that offers contemporary features and seamless integration with
  the GNOME desktop environment.
  


* 2025-05-15 21:37:58 [read]

  A new module is available: `programs.pgcli`
  
  pgcli is a Python CLI that lets you connect to Postgres databases and run queries with syntax highlighting and auto-completion.
  


* 2025-05-12 22:21:57 [read]

  A new module is available: `programs.foliate`
  
  Foliate is a modern e-book reader tailored for GNOME.
  


* 2025-05-11 03:13:09 [read]

  A new module is available: 'programs.halloy'.
  
  Halloy is a modern IRC client supporting IRCv3 features, with a clean and
  intuitive user interface. It provides features like SASL authentication,
  message highlights, nick colors, emoji support, URL previews, and more.
  


* 2025-05-11 01:08:48 [read]

  A new module is available: 'programs.numbat'.
  


* 2025-05-09 03:13:20 [read]

  A new module is available: 'programs.waveterm'.
  
  WaveTerm is a modern, GPU-accelerated terminal emulator that combines the
  power of a traditional terminal with a smart workspace. It provides features
  like automatic command history with contextual search, workspace organization,
  multiple terminals in a single window, and integrated AI assistance.
  


* 2025-05-08 15:45:24 [read]

  A new module is available: 'programs.wayprompt'.
  
  Wayprompt is a password prompter for Wayland, including a drop-in
  replacement for GnuPG’s pinentry ('pinentry-wayprompt').
  
  Note that the Wayland compositor must support the Layer Shell protocol.
  


* 2025-05-08 03:13:52 [read]

  A new module is available: 'programs.lutris'.
  
  Lutris is an open-source gaming platform for Linux. It simplifies the
  installation and management of games from various sources, including Steam,
  GOG, Epic Games Store, Ubisoft Connect, and more. The module allows you to
  configure Lutris settings including runner options, system preferences, and
  interface customization.
  


* 2025-05-05 03:14:02 [read]

  A new module is available: 'programs.sway-easyfocus'.
  
  sway-easyfocus is a tool that provides window switching capabilities for the
  Sway window manager. It works similarly to i3-easyfocus, displaying labels on
  visible windows to allow quick selection and focus without moving your hand to
  the mouse or using directional keys.
  


* 2025-05-04 03:14:11 [read]

  A new module is available: 'programs.i3bar-river'.
  
  i3bar-river is a status bar specifically designed for the River Wayland
  compositor, using the same protocol as i3bar. It allows you to display system
  information and status updates in a customizable bar, and works well with
  tools that output i3bar-compatible JSON like i3status.
  


* 2025-05-03 03:14:19 [read]

  A new module is available: 'programs.onagre'.
  
  Onagre is a simple but flexible application launcher for X11 and Wayland.
  Written in Rust, it features fuzzy search, customizable themes, configurable
  keybindings, and supports executing custom commands. Its design philosophy
  focuses on simplicity and efficiency while remaining highly configurable.
  


* 2025-05-02 03:14:36 [read]

  A new module is available: 'services.clipcat'.
  
  Clipcat is a clipboard manager for Wayland and X11 with a daemon/client
  architecture. It offers a secure way to store and manage clipboard history
  with features like content filtering, custom maximum item count, and
  history persistence. The module provides options to configure the daemon,
  enable clipboard syncing, and set up the included GTK client.
  


* 2025-05-02 03:14:27 [read]

  A new module is available: 'programs.visidata'.
  
  VisiData is a terminal spreadsheet multitool for exploring and arranging data.
  It allows you to quickly open, explore, summarize, and analyze datasets in
  various formats including CSV, Excel, SQL, HTML, JSON, and many more. The
  module lets you configure VisiData's behavior through options and custom key
  bindings.
  


* 2025-04-28 03:17:23 [read]

  A new module is available: 'programs.mpvpaper'.
  
  mpvpaper is a utility that allows you to use videos or complex animations
  as your desktop wallpaper using mpv. It supports various video formats and
  provides configuration options like framerate limits and scaling methods.
  The module allows you to specify target outputs, video options, and
  additional mpv arguments.
  


* 2025-04-28 03:17:15 [read]

  A new module is available: 'programs.kickoff'.
  
  Kickoff is a minimalist application launcher for Wayland designed to be fast
  and lightweight. It features a clean interface that appears at the center of
  the screen, fuzzy search functionality, and customizable appearance through
  theming. The module allows configuration of hotkeys, theme settings, and
  launch options.
  


* 2025-04-27 03:17:07 [read]

  A new module is available: 'programs.rmpc'.
  
  RMPC (Remote MPD Client) is a minimalist TUI client for the Music Player Daemon.
  It provides a simple interface to control MPD with features like playlist
  manipulation, library browsing, and song searching. The module allows you to
  customize its behavior, keybindings, and connection settings.
  


* 2025-04-26 03:16:59 [read]

  A new module is available: 'programs.onedrive'.
  
  OneDrive is Microsoft's cloud storage service. This module integrates
  the open source OneDrive client for Linux which provides synchronization
  capabilities between your local file system and OneDrive. The module allows
  configuring multiple OneDrive accounts, sync options, and notification
  preferences.
  


* 2025-04-21 03:27:49 [read]

  A new module is available: `programs.television`
  
  television is a cross-platform, fast and extensible general purpose fuzzy
  finder TUI.
  


* 2025-04-21 01:44:29 [read]

  A new module is available: 'programs.nix-init'.
  
  nix-init generate Nix packages from URLs.
  


* 2025-04-21 01:12:03 [read]

  A new module is available: 'programs.clock-rs'.
  
  clock-rs is a modern, digital clock that effortlessly runs in your terminal.
  


* 2025-04-20 05:39:01 [read]

  A new module is available: 'programs.wallust'.
  
  Wallust generates colors from an images, similar to pywal.
  


* 2025-04-18 08:58:18 [read]

  A new module is available: 'programs.inori'.
  
  inori is a client for the Music Player Daemon (MPD)
  


* 2025-04-10 08:10:18 [read]

  A new module is available: 'services.way-displays'.
  
  A service to automatically configure your displays on wlroots-based
  wayland compositors.
  


* 2025-04-02 13:01:34 [read]

  A new way to define news is available.
  
  Instead of editing the previous news.nix file, you can now define entries
  using individual files. This should reduce the number of merge conflicts.
  


* 2025-04-02 00:00:00 [read]

  A new service is available: 'services.home-manager.autoExpire'.
  
  A service that allow to automatically expire (and optionally clean-up
  Nix's store) old Home-Manager generations.
  


* 2025-03-29 14:32:11 [read]

  A new module is available: `programs.sesh`
  
  Sesh is a CLI that helps you create and manage tmux sessions quickly and easily using zoxide.
  


* 2025-03-29 04:16:57 [read]

  A new module is available: 'programs.streamlink'.
  
  Streamlink is a CLI utility which pipes video streams from various
  services into a video player.
  


* 2025-03-26 02:44:04 [read]

  A new module is available: `services.mpdscribble`
  
  Adds a module for mpdscribble, a music player daemon scrobbler.
  


* 2025-03-25 23:48:21 [read]

  A new module is available: `programs.ripgrep-all`
  
  Adds a module for ripgrep-all, a tool for searching text in files.
  


* 2025-03-25 20:37:24 [read]

  A new module is available: `programs.mergiraf`
  
  Adds git integration for mergiraf to automatically resolve merge conflicts.
  


* 2025-03-24 22:31:45 [read]

  The following default values change from 'true' to
  'false':
  
  - programs.zellij.enableBashIntegration
  - programs.zellij.enableFishIntegration
  - programs.zellij.enableZshIntegration
  


* 2025-03-24 15:29:33 [read]

  A new module is available: 'programs.smug'.
  
  Session manager and task runner for tmux written in Go.
  See https://github.com/ivaaaan/smug for more information.
  


* 2025-03-21 03:19:14 [read]

  A new module is available: 'programs.distrobox'.
  
  Distrobox is a tool that uses podman or docker to create containers using
  the Linux distribution of your choice. It allows you to use the package
  manager of other distributions to install applications that aren't available
  in NixOS, and integrates those applications with your host system. The module
  enables configuration of container definitions and distrobox settings.
  


* 2025-02-22 16:53:20 [read]

  A new module is available: 'programs.jqp'.
  
  A TUI playground for experimenting with `jq`.
  


* 2025-02-22 16:46:56 [read]

  A new module is available: 'services.wpaperd'.
  
  This replaces the existing module, 'programs.wpaperd', and adds a
  systemd service to ensure its execution.
  


* 2025-02-21 16:53:20 [read]

  A new module is available: 'programs.earthly'.
  
  Earthly is a build configuration framework utilizing buildkit and
  Dockerfile-like syntax for fast builds and simplicity.
  


* 2025-02-20 18:39:31 [read]

  A new module is available: 'programs.swayimg'.
  
  swayimg is a fully customizable and lightweight image viewer for
  Wayland based display servers.
  See https://github.com/artemsen/swayimg for more.
  


* 2025-02-16 17:00:00 [read]

  A new module is available: 'services.wluma'.
  
  Wluma is a tool for Wayland compositors to automatically adjust
  screen brightness based on the screen contents and amount of ambient light around you.
  


* 2025-02-12 15:56:00 [read]

  A new module is available: 'programs.tex-fmt'.
  
  tex-fmt is a LaTeX formatter written in Rust.
  See https://github.com/WGUNDERWOOD/tex-fmt for more information.
  


* 2025-02-11 15:25:26 [read]

  A new module is available: 'programs.git-worktree-switcher'.
  
  git-worktree-switcher allows you to quickly switch git worktrees.
  It includes shell completions for Bash, Fish and Zsh.
  See https://github.com/mateusauler/git-worktree-switcher for more.
  


* 2025-02-07 22:31:45 [read]

  All 'programs.<PROGRAM>.enable<SHELL>Integration' values now default
  to the new 'home.shell.enable<SHELL>Integration' options, which
  inherit from the new the 'home.shell.enableShellIntegration' option.
  
  The following inconsistent default values change from 'false' to
  'true':
  
  - programs.zellij.enableBashIntegration
  - programs.zellij.enableFishIntegration
  - programs.zellij.enableZshIntegration
  


* 2025-01-30 09:18:55 [read]

  A new module is available: 'services.linux-wallpaperengine'.
  
  Reproduce the background functionality of Wallpaper Engine on Linux
  systems.
  


* 2025-01-26 16:40:00 [read]

  A new module is available: 'programs.mods'
  
  mods is a command line AI tool that is highly configurable and allows
  querying AI models hosted locally or by other services (OpenAI,
  Cohere, Groq).
  


* 2025-01-04 15:00:00 [read]

  A new module is available: 'wayland.windowManager.wayfire'.
  
  Wayfire is a 3D Wayland compositor, inspired by Compiz and based on
  wlroots. It aims to create a customizable, extendable and lightweight
  environment without sacrificing its appearance.
  
  This Home Manager module allows you to configure both wayfire itself,
  as well as wf-shell.
  


* 2025-01-02 11:21:19 [read]

  A new module is available: 'services.mpdscribble'.
  
  A MPD client which submits information about tracks being played to a
  scrobbler (e.g. last.fm)
  


* 2025-01-01 23:16:35 [read]

  A new module is available: 'programs.ghostty'.
  
  Ghostty is a terminal emulator that differentiates itself by being
  fast, feature-rich, and native. While there are many excellent
  terminal emulators available, they all force you to choose between
  speed, features, or native UIs. Ghostty provides all three.
  


* 2025-01-01 15:31:15 [read]

  The 'systemd.user.startServices' option now defaults to 'true',
  meaning that services will automatically be restarted as needed when
  activating a configuration.
  
  Further, the "legacy" alternative has been removed and will now result
  in an evaluation error if used.
  
  The "suggest" alternative will remain for a while longer but may also
  be deprecated for removal in the future.
  


* 2024-12-22 08:24:29 [read]

  A new module is available: 'programs.cavalier'.
  
  Cavalier is a GUI wrapper around the Cava audio visualizer.
  


* 2024-12-21 17:07:49 [read]

  A new module is available: 'programs.pay-respects'.
  
  Pay Respects is a shell command suggestions tool and command-not-found
  and thefuck replacement written in Rust.
  


* 2024-12-04 20:00:00 [read]

  
  A new option 'programs.starship.enableInteractive' is available for
  the Fish shell that only enables starship if the shell is interactive.
  
  Some plugins require this to be set to 'false' to function correctly.
  


* 2024-12-01 19:34:04 [read]

  
  A new module is available: 'programs.kubecolor'.
  
  Kubecolor is a kubectl wrapper used to add colors to your kubectl
  output.
  


* 2024-12-01 19:17:40 [read]

  
  A new module is available: 'programs.nix-your-shell'.
  
  nix-your-shell is a wrapper for `nix develop` or `nix-shell` to retain
  the same shell inside the new environment.
  


* 2024-11-01 19:44:59 [read]

  
  A new module is available: 'services.podman'.
  
  Podman is a daemonless container engine that lets you manage
  containers, pods, and images.
  
  This Home Manager module allows you to define containers that will run
  as systemd services.
  


* 2024-10-25 08:18:30 [read]

  
  A new module is available: 'nixGL'.
  
  NixGL solve the "OpenGL" problem with nix. The 'nixGL' module provides
  integration of NixGL into Home Manager. See the "GPU on non-NixOS
  systems" section in the Home Manager manual for more.
  


* 2024-10-20 07:53:54 [read]

  
  A new module is available: 'programs.nh'.
  
  nh is yet another Nix CLI helper. Adding functionality on top of the
  existing solutions, like nixos-rebuild, home-manager cli or nix
  itself.
  


* 2024-10-18 14:01:07 [read]

  
  A new module is available: 'programs.cmus'.
  
  cmus is a small, fast and powerful console music player.
  


* 2024-10-17 13:07:55 [read]

  
  A new module is available: 'programs.zed-editor'.
  
  Zed is a fast text editor for macOS and Linux.
  See https://zed.dev for more.
  


* 2024-10-11 08:23:19 [read]

  
  A new module is available: 'programs.vifm'.
  
  Vifm is a curses based Vim-like file manager extended with some useful
  ideas from mutt.
  


* 2024-10-09 06:16:23 [read]

  
  A new module is available: 'services.snixembed'.
  
  snixembed proxies StatusNotifierItems as XEmbedded systemtray-spec
  icons. This is useful for some tools in some environments, e.g., Safe
  Eyes in i3, lxde or mate.
  


* 2024-09-20 07:00:11 [read]

  
  The option 'programs.kitty.theme' has been deprecated, please use
  'programs.kitty.themeFile' instead.
  
  The 'programs.kitty.themeFile' option expects the file name of a
  theme from `kitty-themes`, without the `.conf` suffix. See
  <https://github.com/kovidgoyal/kitty-themes/tree/master/themes> for a
  list of themes.
  


* 2024-09-13 09:50:49 [read]

  
  A new module is available: 'programs.neovide'.
  
  Neovide is a simple, no-nonsense, cross-platform graphical user
  interface for Neovim (an aggressively refactored and updated Vim
  editor).
  


* 2024-09-13 08:58:17 [read]

  
  A new module is available: 'services.trayscale'.
  
  An unofficial GUI wrapper around the Tailscale CLI client.
  


* 2024-08-18 11:42:08 [read]

  
  A new module is available: 'programs.lapce'.
  
  Lightning-fast and Powerful Code Editor written in Rust.
  See https://lapce.dev/ for more.
  


* 2024-06-28 14:18:16 [read]

  
  A new module is available: 'services.glance'.
  
  Glance is a self-hosted dashboard that puts all your feeds in
  one place. See https://github.com/glanceapp/glance for more.
  


* 2024-06-22 05:49:48 [read]

  
  A new module is available: 'services.blanket'.
  
  Blanket is a program you can use to improve your focus and increase
  your productivity by listening to different sounds. See
  https://github.com/rafaelmardojai/blanket for more.
  


* 2024-05-25 14:36:03 [read]

  
  Multiple new options are available:
  
  - 'nix.nixPath'
  - 'nix.keepOldNixPath'
  - 'nix.channels'
  


* 2024-05-21 20:22:57 [read]

  
  The Git module now supports signing via SSH and X.509 keys, in addition to OpenPGP/GnuPG,
  via the `programs.git.signing.format` option.
  
  The format defaults to `openpgp` for now, due to backwards compatibility reasons — this is
  not guaranteed to last! GPG users should manually set `programs.git.signing.format` to
  `openpgp` as soon as possible.
  
  Accordingly, `programs.git.signing.gpgPath` has been renamed to the more generic option
  `programs.git.signing.signer` as not everyone uses GPG.
  Please migrate to the new option to suppress the generated warning.
  


* 2024-05-10 21:28:38 [read]

  
  A new module is available: 'programs.yambar'.
  
  Yambar is a lightweight and configurable status panel for X11 and
  Wayland, that goes to great lengths to be both CPU and battery
  efficient - polling is only done when absolutely necessary.
  
  See https://codeberg.org/dnkl/yambar for more.
  


* 2024-05-10 13:35:19 [read]

  
  A new module is available: 'services.hyprpaper'.
  
  Hyprpaper is a blazing fast wallpaper utility for Hyprland with the
  ability to dynamically change wallpapers through sockets. It will work
  on all wlroots-based compositors, though. See
  https://github.com/hyprwm/hyprpaper for more.
  


* 2024-05-10 11:48:34 [read]

  
  A new module is available: 'programs.hyprlock'.
  
  Hyprland's simple, yet multi-threaded and GPU-accelerated screen
  locking utility. See https://github.com/hyprwm/hyprlock for more.
  


* 2024-05-10 10:30:58 [read]

  
  A new module is available: 'programs.fastfetch'.
  
  Fastfetch is a Neofetch-like tool for fetching system information and
  displaying them in a pretty way. See
  https://github.com/fastfetch-cli/fastfetch for more.
  


* 2024-05-06 07:36:13 [read]

  
  A new module is available: 'programs.gnome-shell'.
  
  GNOME Shell is the graphical shell of the GNOME desktop environment.
  It provides basic functions like launching applications and switching
  between windows, and is also a widget engine.
  


* 2024-05-05 07:22:01 [read]

  
  A new module is available: 'services.hypridle'.
  
  Hypridle is a program that monitors user activity and runs commands
  when idle or active. See https://github.com/hyprwm/hypridle for more.
  


* 2024-04-30 21:57:23 [read]

  
  A new module is available: 'services.conky'.
  
  Conky is a system monitor for X. Conky can display just about
  anything, either on your root desktop or in its own window. See
  https://conky.cc/ for more.
  


* 2024-04-30 18:28:28 [read]

  
  A new module is available: 'programs.freetube'.
  
  FreeTube is a YouTube client built around using YouTube more
  privately. You can enjoy your favorite content and creators without
  your habits being tracked. See https://freetubeapp.io/ for more.
  


* 2024-04-29 22:01:51 [read]

  
  A new module is available: 'services.swaync'.
  
  SwayNotificationCenter is a simple notification daemon with a GTK GUI
  for notifications and the control center. See
  https://github.com/ErikReider/SwayNotificationCenter for more.
  


* 2024-04-28 20:27:08 [read]

  
  A new module is available: 'services.psd'.
  
  Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage
  your browser's profile in tmpfs and to periodically sync it back to
  your physical disc (HDD/SSD).
  


* 2024-04-22 18:04:47 [read]

  
  A new module is available: 'services.amberol'.
  
  Amberol is a music player with no delusions of grandeur. If you just
  want to play music available on your local system then Amberol is the
  music player you are looking for. See https://apps.gnome.org/Amberol/
  for more.
  


* 2024-04-21 20:53:09 [read]

  
  A new module is available: 'programs.poetry'.
  
  Poetry is a tool that helps you manage Python project dependencies and
  packages. See https://python-poetry.org/ for more.
  


* 2024-04-19 14:53:17 [read]

  
  A new module is available: 'services.remmina'.
  


* 2024-04-19 10:01:55 [read]

  
  A new module is available: 'programs.spotify-player'.
  


* 2024-04-19 09:23:52 [read]

  
  A new module is available: 'programs.tofi'.
  


* 2024-04-18 22:30:49 [read]

  
  A new module is available: 'programs.fd'.
  


* 2024-04-08 21:43:38 [read]

  
  A new module is available: 'programs.bun'.
  


* 2024-03-28 17:02:19 [read]

  
  A new module is available: 'services.amberol'.
  


* 2024-03-15 08:39:52 [read]

  
  A new module is available: 'services.activitywatch'.
  


* 2024-03-13 13:28:22 [read]

  
  A new module is available: 'programs.joplin-desktop'.
  


* 2024-03-08 22:23:24 [read]

  
  A new module is available: 'programs.ranger'.
  


* 2024-03-08 22:20:04 [read]

  
  A new module is available: 'programs.zk'
  


* 2024-02-21 23:01:27 [read]

  
  A new module is available: 'wayland.windowManager.river'.
  


* 2024-02-05 22:45:37 [read]

  
  A new module is available: 'programs.jetbrains-remote'
  


* 2024-02-05 22:33:54 [read]

  
  A new module is available: 'services.arrpc'
  


* 2024-01-27 22:53:00 [read]

  
  A new module is available: 'services.wob'.
  


* 2024-01-20 23:45:07 [read]

  
  A new module is available: 'programs.mise'.
  
  This module replaces 'programs.rtx', which has been removed.
  


* 2024-01-03 19:25:09 [read]

  
  A new module is available: 'xdg.portal'.
  


* 2024-01-01 09:09:42 [read]

  
  A new module is available: 'programs.i3blocks'.
  


* 2023-12-29 08:22:40 [read]

  
  A new module is available: 'programs.bemenu'.
  


* 2023-12-28 13:01:15 [read]

  
  A new module is available: 'programs.sftpman'.
  


* 2023-12-28 08:28:26 [read]

  
  A new module is available: 'services.osmscout-server'.
  


* 2023-12-20 11:41:10 [read]

  
  A new module is available: 'programs.gradle'.
  


* 2023-12-19 22:57:52 [read]

  
  A new module is available: 'programs.sapling'.
  


* 2023-11-26 23:18:01 [read]

  
  A new module is available: 'services.signaturepdf'.
  


* 2023-11-22 22:42:16 [read]

  
  A new module is available: 'programs.ruff'.
  


* 2023-11-01 21:18:20 [read]

  
  A new module is available: 'programs.granted'.
  


* 2023-10-24 06:14:53 [read]

  
  A new module is available: 'programs.cava'.
  


* 2023-10-17 06:33:24 [read]

  
  A new module is available: 'services.darkman'.
  


* 2023-10-04 18:35:42 [read]

  
  A new module is available: 'programs.openstackclient'.
  


* 2023-10-04 06:44:15 [read]

  
  A new module is available: 'programs.thefuck'.
  


* 2023-10-01 07:28:45 [read]

  
  A new module is available: 'programs.khard'.
  


* 2023-10-01 07:23:26 [read]

  
  A new module is available: 'programs.wpaperd'.
  


* 2023-09-30 07:47:23 [read]

  
  A new module is available: 'programs.awscli'.
  


* 2023-09-24 10:06:47 [read]

  
  A new module is available: 'programs.bacon'.
  


* 2023-09-18 11:44:11 [read]

  
  A new module is available: 'programs.rio'.
  
  Rio is a hardware-accelerated GPU terminal emulator powered by WebGPU.
  


* 2023-09-07 14:52:19 [read]

  
  A new module is available: 'programs.eza'.
  


* 2023-09-05 06:38:05 [read]

  
  A new module is available: 'programs.carapace'.
  


* 2023-08-23 12:01:06 [read]

  
  A new module is available: 'programs.yazi'.
  


* 2023-08-22 16:06:52 [read]

  
  A new module is available: 'programs.qcal'.
  


* 2023-08-16 15:43:30 [read]

  
  A new module is available: 'programs.pqiv'.
  


* 2023-08-15 15:45:45 [read]

  
  A new module is available: 'programs.xplr'.
  


* 2023-07-24 10:38:23 [read]

  
  A new module is available: 'programs.gh-dash'
  


* 2023-07-20 21:56:49 [read]

  
  A new module is available: 'wayland.windowManager.hyprland'
  


* 2023-07-08 09:44:56 [read]

  
  A new module is available: 'services.swayosd'
  


* 2023-07-08 09:21:06 [read]

  
  A new module is available: 'programs.pyenv'.
  


* 2023-07-08 08:27:41 [read]

  
  A new modules is available: 'programs.darcs'
  


* 2023-06-30 14:46:22 [read]

  
  A new module is available: 'services.ssh-agent'
  


* 2023-06-14 21:41:22 [read]

  
  Two new modules are available:
  
    - 'programs.comodoro' and
    - 'services.comodoro'
  


* 2023-06-14 21:25:34 [read]

  
  A new module is available: 'programs.git-credential-oauth'.
  


* 2023-06-09 19:13:39 [read]

  
  A new module is available: 'programs.boxxy'.
  


* 2023-06-07 12:16:55 [read]

  
  A new module is available: 'programs.imv'.
  


* 2023-06-07 06:01:16 [read]

  
  A new module is available: 'programs.rtx'.
  


* 2023-06-03 22:19:32 [read]

  
  A new module is available: 'programs.ripgrep'.
  


* 2023-05-18 21:03:30 [read]

  
  A new module is available: 'programs.script-directory'.
  


* 2023-05-13 13:51:18 [read]

  
  A new module is available: 'programs.fuzzel'.
  


* 2023-05-12 21:31:05 [read]

  
  A new module is available: 'programs.translate-shell'.
  


* 2023-05-09 16:06:56 [read]

  
  A new module is available: 'programs.git-cliff'.
  


* 2023-04-28 19:59:23 [read]

  
  A new module is available: 'programs.jujutsu'.
  


* 2023-04-19 15:33:07 [read]

  
  A new module is available: 'programs.mr'.
  


* 2023-04-18 06:28:31 [read]

  
  A new module is available: 'services.batsignal'.
  


* 2023-03-25 14:53:57 [read]

  
  A new module is available: 'programs.hstr'.
  


* 2023-03-22 07:31:38 [read]

  
  A new module is available: 'services.copyq'.
  


* 2023-03-22 07:20:00 [read]

  
  A new module is available: 'services.listenbrainz-mpd'.
  


* 2023-02-22 22:16:37 [read]

  
  A new module is available: 'services.avizo'.
  


* 2023-02-20 22:31:23 [read]

  
  A new module is available: 'services.mpd-mpris'.
  


* 2023-02-02 20:49:05 [read]

  
  A new module is available: 'services.autorandr'.
  


* 2023-01-31 22:08:41 [read]

  
  A new module is available: 'programs.rbenv'.
  


* 2023-01-30 10:39:11 [read]

  
  A new module is available: 'programs.wlogout'.
  


* 2023-01-28 17:35:49 [read]

  
  A new module is available: 'programs.papis'.
  


* 2023-01-07 10:47:03 [read]

  
  'xsession.windowManager.i3.config.[window|floating].titlebar' and
  'wayland.windowManager.sway.config.[window|floating].titlebar' now default to 'true'.
  


* 2022-12-28 21:48:22 [read]

  
  A new module is available: 'services.clipman'.
  


* 2022-12-25 08:41:32 [read]

  
  A new module is available: 'services.cachix-agent'.
  


* 2022-12-16 15:01:20 [read]

  
  A new module is available: 'services.megasync'.
  


* 2022-11-04 14:56:46 [read]

  
  A new module is available: 'programs.thunderbird'.
  


* 2022-11-02 10:56:14 [read]

  
  A new module is available: 'xfconf'.
  


* 2022-11-01 23:57:50 [read]

  
  A new module is available: 'programs.oh-my-posh'.
  


* 2022-10-24 22:05:27 [read]

  
  A new module is available: 'programs.k9s'.
  


* 2022-10-18 08:07:43 [read]

  
  A new module is available: 'programs.looking-glass-client'.
  


* 2022-10-16 19:49:46 [read]

  
  Two new modules are available:
  
    - 'programs.borgmatic' and
    - 'services.borgmatic'.
  
  use the first to configure the borgmatic tool and the second if you
  want to automatically run scheduled backups.
  


* 2022-10-12 23:10:48 [read]

  
  A new module is available: 'programs.discocss'.
  


* 2022-10-06 23:19:10 [read]

  
  A new module is available: 'programs.havoc'.
  


* 2022-10-06 23:06:08 [read]

  
  A new module is available: 'programs.ledger'.
  


* 2022-09-29 13:43:02 [read]

  
  A new module is available: 'programs.pls'.
  


* 2022-09-25 22:22:17 [read]

  
  A new module is available: 'programs.tmate'.
  


* 2022-09-25 21:00:05 [read]

  
  A new module is available: 'services.safeeyes'.
  


* 2022-09-21 22:42:42 [read]

  
  A new module is available: 'xsession.windowManager.fluxbox'.
  


* 2022-09-09 09:55:50 [read]

  
  A new module is available: 'programs.gallery-dl'.
  


* 2022-09-08 17:50:43 [read]

  
  A new module is available: 'programs.yt-dlp'.
  


* 2022-09-08 15:41:46 [read]

  
  A new module is available: 'programs.nheko'.
  


* 2022-09-05 12:33:11 [read]

  
  A new module is available: 'programs.btop'.
  


* 2022-09-05 11:05:25 [read]

  
  A new module is available: 'editorconfig'.
  


* 2022-08-25 21:01:37 [read]

  
  A new module is available: 'services.pueue'.
  


* 2022-08-08 16:11:22 [read]

  
  A new module is available: 'programs.bashmount'.
  


* 2022-08-07 09:07:35 [read]

  
  A new module is available: 'programs.wezterm'.
  


* 2022-08-01 16:35:28 [read]

  
  A new module is available: 'programs.hyfetch'.
  


* 2022-07-27 12:22:37 [read]

  
  A new module is available: 'services.recoll'.
  


* 2022-07-25 11:29:14 [read]

  
  A new module is available: 'xsession.windowManager.spectrwm'.
  


* 2022-07-13 13:28:54 [read]

  
  A new module is available: 'programs.librewolf'.
  


* 2022-06-26 19:29:25 [read]

  
  A new module is available: 'services.sctd'.
  


* 2022-06-24 22:40:27 [read]

  
  A new module is available: 'programs.pistol'.
  


* 2022-06-24 17:18:32 [read]

  
  A new module is available: 'programs.micro'.
  


* 2022-06-21 22:29:37 [read]

  
  A new module is available: 'programs.mujmap'.
  


* 2022-05-18 22:09:45 [read]

  
  A new module is available: 'services.mopidy'.
  


* 2022-05-02 20:55:46 [read]

  
  A new module is available: 'programs.tealdeer'.
  


* 2022-03-13 20:59:38 [read]

  
  A new module is available: 'services.fusuma'.
  


* 2022-03-06 09:40:17 [read]

  
  A new module is available: 'programs.pubs'.
  


* 2022-03-06 08:50:32 [read]

  
  A new module is available: 'programs.just'.
  


* 2022-02-24 22:35:22 [read]

  
  A new module is available: 'programs.gitui'.
  


* 2022-02-17 23:11:13 [read]

  
  A new module is available: 'services.espanso'.
  


* 2022-02-17 17:12:46 [read]

  
  A new module is available: 'programs.eww'.
  


* 2022-02-16 23:50:35 [read]

  
  A new module is available: 'programs.zellij'.
  


* 2022-02-03 23:23:49 [read]

  
  A new module is available: 'services.twmn'.
  


* 2022-01-26 22:08:29 [read]

  
  A new module is available: 'programs.kodi'.
  


* 2022-01-22 17:39:20 [read]

  
  A new module is available: 'programs.pandoc'.
  


* 2022-01-22 16:54:31 [read]

  
  A new module is available: 'programs.tint2'.
  


* 2022-01-22 15:33:42 [read]

  
  A new module is available: 'programs.timidity'.
  


* 2022-01-22 15:12:20 [read]

  
  A new module is available: 'programs.watson'.
  


* 2022-01-22 14:36:25 [read]

  
  A new module is available: 'programs.helix'.
  


* 2022-01-11 12:26:43 [read]

  
  A new module is available: 'programs.sagemath'.
  


* 2022-01-03 10:34:45 [read]

  
  A new module is available: 'services.swayidle'.
  


* 2021-12-31 09:39:20 [read]

  
  A new module is available: 'xsession.windowManager.herbstluftwm'.
  


* 2021-12-21 22:17:30 [read]

  
  A new module is available: 'services.systembus-notify'.
  


* 2021-12-12 17:09:38 [read]

  
  A new module is available: 'services.opensnitch-ui'.
  


* 2021-12-11 16:07:00 [read]

  
  A new module is available: 'services.gromit-mpx'.
  


* 2021-12-11 11:55:12 [read]

  
  A new module is available: 'programs.navi'.
  


* 2021-12-10 23:19:57 [read]

  
  A new module is available: 'programs.sqls'.
  


* 2021-11-30 22:28:12 [read]

  
  A new module is available: 'programs.less'.
  


* 2021-10-23 17:12:22 [read]

  
  A new module is available: 'programs.hexchat'.
  


* 2021-10-05 22:15:00 [read]

  
  A new module is available: 'programs.nnn'.
  


* 2021-10-05 20:55:07 [read]

  
  A new module is available: 'programs.atuin'.
  


* 2021-09-14 21:31:03 [read]

  
  A new module is available: 'programs.bottom'.
  


* 2021-08-31 18:44:26 [read]

  
  A new module is available: 'services.betterlockscreen'.
  


* 2021-08-26 06:40:59 [read]

  
  A new module is available: 'services.fnott'.
  


* 2021-08-16 21:59:02 [read]

  
  A new module is available: 'services.git-sync'.
  


* 2021-08-11 13:55:51 [read]

  
  A new module is available: 'services.easyeffects'.
  


* 2021-08-10 21:28:40 [read]

  
  A new module is available: 'programs.java'.
  


* 2021-07-23 22:22:31 [read]

  
  A new module is available: 'services.trayer'.
  


* 2021-07-19 01:30:46 [read]

  
  A new module is available: 'services.notify-osd'.
  


* 2021-07-15 13:38:32 [read]

  
  A new module is available: 'services.xsettingsd'.
  


* 2021-07-14 20:06:18 [read]

  
  A new module is available: 'services.volnoti'.
  


* 2021-07-11 17:45:56 [read]

  
  A new module is available: 'programs.sm64ex'.
  


* 2021-06-24 22:36:11 [read]

  
  A new module is available: 'i18n.inputMethod'.
  


* 2021-06-22 14:43:53 [read]

  
  A new module is available: 'programs.himalaya'.
  


* 2021-06-16 01:26:16 [read]

  
  The xmonad module now compiles the configuration before
  linking the binary to the place xmonad expects to find
  the compiled configuration (the binary).
  
  This breaks recompilation of xmonad (i.e. the 'q' binding or
  'xmonad --recompile').
  
  If this behavior is undesirable, do not use the
  'xsession.windowManager.xmonad.config' option. Instead, set the
  contents of the configuration file with
  'home.file.".xmonad/config.hs".text = "content of the file"'
  or 'home.file.".xmonad/config.hs".source = ./path-to-config'.
  


* 2021-06-12 05:00:22 [read]

  
  A new module is available: 'programs.mangohud'.
  


* 2021-06-07 20:44:00 [read]

  
  A new module is available: 'services.pantalaimon'.
  


* 2021-06-02 04:24:10 [read]

  
  A new module is available: 'services.xidlehook'.
  


* 2020-04-26 13:32:17 [read]

  
  A number of new modules are available:
  
    - 'accounts.calendar',
    - 'accounts.contact',
    - 'programs.khal',
    - 'programs.vdirsyncer', and
    - 'services.vdirsyncer' (Linux only).
  
  The two first modules offer a number of options for
  configuring calendar and contact accounts. This includes,
  for example, information about carddav and caldav servers.
  
  The khal and vdirsyncer modules make use of this new account
  infrastructure.
  
  Note, these module are still somewhat experimental and their
  structure should not be seen as final, some modifications
  may be necessary as new modules are added.
  
