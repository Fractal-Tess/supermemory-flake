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
  ports = [ cfg.port ] ++ lib.optional cfg.mcp.enable cfg.mcp.port;
in
{
  options = lib.recursiveUpdate (import ./options.nix { inherit lib package mcpPackage; }) {
    services.supermemory-server = {
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/supermemory";
        description = "Where the database, generated API key, and embedding model cache live.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "supermemory";
        description = "User the server runs as. Created when left at the default.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "supermemory";
        description = "Group the server runs as. Created when left at the default.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the port on all interfaces.";
      };

      firewallInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "wt0" ];
        description = "Interfaces to open the port on, such as a VPN interface.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.users = lib.mkIf (cfg.user == "supermemory") {
      supermemory = {
        isSystemUser = true;
        inherit (cfg) group;
        home = cfg.dataDir;
      };
    };
    users.groups = lib.mkIf (cfg.group == "supermemory") { supermemory = { }; };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -" ];

    systemd.services.supermemory-server = {
      description = "Supermemory server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = import ./environment.nix { inherit lib cfg; } // {
        HOME = cfg.dataDir;
        SUPERMEMORY_DATA_DIR = cfg.dataDir;
      };
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # It keeps no state and no credentials (callers send their own key), so it
    # runs as a throwaway user.
    systemd.services.supermemory-mcp = lib.mkIf cfg.mcp.enable {
      description = "Supermemory MCP endpoint";
      after = [ "supermemory-server.service" ];
      wants = [ "supermemory-server.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        SUPERMEMORY_API_URL = "http://127.0.0.1:${toString cfg.port}";
        SUPERMEMORY_MCP_PORT = toString cfg.mcp.port;
      };
      serviceConfig = {
        ExecStart = lib.getExe cfg.mcp.package;
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall ports;
    networking.firewall.interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
      allowedTCPPorts = ports;
    });
  };
}
