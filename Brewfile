# Homebrew packages — canonical source of truth.
# Add or remove a line here and run update-all (or brew.sh) to sync.
# `brew bundle install --cleanup` will install new entries and remove unlisted ones.

tap "dicklesworthstone/tap"

# cass: unified search over local coding-agent session history (not in nixpkgs), used by
# the search-agent-history skill. https://github.com/Dicklesworthstone/coding_agent_session_search
# Main data stores it indexes here:
#   Claude Code  ~/.claude/projects/<cwd-slug>/<session>.jsonl (+ <session>/subagents/*.jsonl)  JSONL
#   OpenCode     ~/.local/share/opencode/opencode.db (session/message/part tables)               SQLite
#   Devin CLI    ~/.local/share/devin/cli/sessions.db (branching message tree)                   SQLite
brew "dicklesworthstone/tap/cass", trusted: true  # trust this formula only, not the whole tap (Homebrew 7 trust store)

brew "fvm"                       # Flutter version manager
brew "git-credential-libsecret"  # Git credential helper using libsecret keyring
brew "icu4c@76"                  # ICU Unicode library (versioned formula)
brew "nvm"                       # Node Version Manager
brew "network-doctor"            # Network troubleshooting https://github.com/heymaikol/network-doctor
