# Environment shared by the NixOS and Home Manager services.
{ lib, cfg }:
{
  PORT = toString cfg.port;
}
// lib.optionalAttrs (!cfg.telemetry) { SUPERMEMORY_DISABLE_TELEMETRY = "1"; }
// cfg.environment
