{ pkgs, lib, ... }:

{
  systemd.user.services.ollama = {
    Unit = {
      Description = "Ollama AI model server";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.ollama-vulkan}/bin/ollama serve";
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

  systemd.user.services.jackett = {
    Unit = {
      Description = "Jackett torrent indexer proxy";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.jackett}/bin/jackett --NoRestart --NoUpdates";
      Restart = "always";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home.packages = [ pkgs.ollama-vulkan ];

}
