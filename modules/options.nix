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

    llm = {
      baseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://openrouter.ai/api/v1";
        description = ''
          OpenAI-compatible endpoint for the model that chunks text and
          extracts memories: OpenRouter, Ollama, llama.cpp, and so on. Null
          leaves the provider to whichever key is in `environmentFile`. Put
          the key itself there as `OPENAI_API_KEY`.
        '';
      };

      model = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "google/gemini-2.5-flash";
        description = "Model id sent to that endpoint. It must support tool calling.";
      };
    };

    embeddings = {
      provider = lib.mkOption {
        type = lib.types.enum [
          "local"
          "openai"
          "openai-compatible"
          "google"
        ];
        default = "local";
        description = ''
          Where text is embedded for semantic search. `local` runs a small
          model on this machine's CPU. `openai-compatible` uses `baseUrl`,
          with `OPENAI_API_KEY` from `environmentFile`.
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://openrouter.ai/api/v1";
        description = "Endpoint for `openai-compatible` embeddings.";
      };

      model = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "openai/text-embedding-3-small";
        description = "Embedding model id. Null keeps the provider's default.";
      };

      dimensions = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 2000);
        default = null;
        example = 1536;
        description = ''
          Vector size the model produces; the index cannot exceed 2000. Set it
          together with `model`. It is fixed once data exists: changing the
          model or size later needs a fresh data directory.
        '';
      };
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
