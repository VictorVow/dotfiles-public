# Repo maintenance tasks. Tools come from the flake's devShell (nix/flake.nix).

dev := "nix develop ./nix --command"

# List recipes
default:
    @just --list

# Everything: flake checks (HM build, statix, deadnix, shellcheck) + Ansible linters
check: check-flake lint-ansible

# nix flake check — builds the HM activation package, so it can take a while
check-flake:
    nix flake check ./nix

# Fast lints only (no HM build)
lint: lint-nix lint-shell lint-ansible

lint-nix:
    {{dev}} sh -c 'statix check -c nix/statix.toml nix && deadnix --fail nix'

lint-shell:
    {{dev}} sh -c "git ls-files -z '*.sh' ':!:docs/archive/*' | xargs -0 shellcheck -x -S warning"

lint-ansible:
    {{dev}} sh -c 'yamllint ansible.yml custom-installers.yml && ansible-lint -q ansible.yml custom-installers.yml'

# Point git at the tracked hooks in .githooks/ (once per clone)
install-hooks:
    git config core.hooksPath .githooks
