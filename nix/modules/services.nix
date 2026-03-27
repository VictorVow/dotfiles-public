{ pkgs, lib, ... }:

{
  systemd.user.services.ollama = {
    Unit = {
      Description = "Ollama AI model server";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.ollama}/bin/ollama serve";
      Restart = "always";
      RestartSec = "3";
      Environment = [
        "OLLAMA_HOST=127.0.0.1:11434"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home.packages = [ pkgs.ollama ];

  # Pull the embedding model for Logseq vector search on first hms.
  # nomic-embed-text is ~274 MB; swap for qwen3-embedding:8b for higher quality.
  home.activation.ollamaEmbedModel = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if command -v ollama &>/dev/null; then
      if ! ollama list 2>/dev/null | grep -q "nomic-embed-text"; then
        echo "Pulling Ollama embedding model nomic-embed-text…"
        $DRY_RUN_CMD ollama pull nomic-embed-text || true
      fi
    fi
  '';
}
