---
name: direnv-ignored
description: Setup nix-direnv in this repo without having to commit it.
---
1. Create `.envrc` in the top-level of repo with the content `use flake "path:$PWD/.nix"`.
2. Append to the repo `.git/info/exclude` this content: `.nix/`.
3. Create `.nix/flake.nix` with the packages needed in this project environment.
4. Execute `direnv allow` in order to activate nix-direnv and setup the project environment.
