{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = self.packages.${pkgs.stdenv.hostPlatform.system}.supermemory-server;
  mcpPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.supermemory-mcp;
  cfg = config.services.supermemory-server;
in
{
  options = lib.recursiveUpdate (import ./options.nix { inherit lib package mcpPackage; }) {
    services.supermemory-server.dataDir = lib.mkOption {
      type = lib.types.str;
      default = "%h/.local/share/supermemory";
      description = "Where the database, generated API key, and embedding model cache live.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.supermemory-server = {
      Unit = {
        Description = "Supermemory server";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStartPre = "${lib.getExe' pkgs.coreutils "mkdir"} -p ${cfg.dataDir}";
        ExecStart = lib.getExe cfg.package;
        WorkingDirectory = "%h";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") (
          import ./environment.nix { inherit lib cfg; } // { SUPERMEMORY_DATA_DIR = cfg.dataDir; }
        );
        Restart = "on-failure";
        RestartSec = 5;
      }
      // lib.optionalAttrs (cfg.environmentFile != null) { EnvironmentFile = cfg.environmentFile; };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.supermemory-mcp = lib.mkIf cfg.mcp.enable {
      Unit = {
        Description = "Supermemory MCP endpoint";
        After = [ "supermemory-server.service" ];
        Wants = [ "supermemory-server.service" ];
      };
      Service = {
        ExecStart = lib.getExe cfg.mcp.package;
        Environment = [
          "SUPERMEMORY_API_URL=http://127.0.0.1:${toString cfg.port}"
          "SUPERMEMORY_MCP_PORT=${toString cfg.mcp.port}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
