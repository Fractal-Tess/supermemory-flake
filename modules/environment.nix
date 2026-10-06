# Environment shared by the NixOS and Home Manager services.
{ lib, cfg }:
{
  PORT = toString cfg.port;
}
// lib.optionalAttrs (!cfg.telemetry) { SUPERMEMORY_DISABLE_TELEMETRY = "1"; }
// lib.optionalAttrs (cfg.llm.baseUrl != null) { OPENAI_BASE_URL = cfg.llm.baseUrl; }
// lib.optionalAttrs (cfg.llm.model != null) { OPENAI_MODEL = cfg.llm.model; }
// lib.optionalAttrs (cfg.embeddings.provider != "local" || cfg.embeddings.model != null) {
  SUPERMEMORY_EMBEDDING_PROVIDER = cfg.embeddings.provider;
}
// lib.optionalAttrs (cfg.embeddings.baseUrl != null) {
  SUPERMEMORY_EMBEDDING_BASE_URL = cfg.embeddings.baseUrl;
}
// lib.optionalAttrs (cfg.embeddings.model != null) {
  SUPERMEMORY_EMBEDDING_MODEL = cfg.embeddings.model;
}
// lib.optionalAttrs (cfg.embeddings.dimensions != null) {
  SUPERMEMORY_EMBEDDING_DIMENSIONS = toString cfg.embeddings.dimensions;
}
// cfg.environment
