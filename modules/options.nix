{
  lib,
  package,
  mcpPackage,
}:
{
  services.supermemory-server = {
    enable = lib.mkEnableOption "the self-hosted Supermemory server";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "Supermemory server package to run.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Port for the HTTP API. The server listens on every interface.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        OPENAI_BASE_URL = "http://localhost:11434/v1";
        OPENAI_MODEL = "gpt-oss:20b";
      };
      description = ''
        Extra environment variables, such as the LLM endpoint and model used
        for memory extraction. Put keys in `environmentFile` instead.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/supermemory.env";
      description = ''
        File with `KEY=value` lines loaded into the service, for secrets such
        as `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`. It is read at start, so it
        stays out of the Nix store.
      '';
    };

    mcp = {
      enable = lib.mkEnableOption ''
        an MCP endpoint in front of the server. The self-hosted binary has
        none, and coding-agent plugins need one for their memory tools
      '';

      package = lib.mkOption {
        type = lib.types.package;
        default = mcpPackage;
        description = "MCP endpoint package to run.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6768;
        description = "Port for the MCP endpoint, served at /mcp on every interface.";
      };
    };

    telemetry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Leave upstream telemetry on. Off sets SUPERMEMORY_DISABLE_TELEMETRY=1.";
    };
  };
}
