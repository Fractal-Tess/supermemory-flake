{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs,
}:

# The self-hosted server has no MCP endpoint, so this small Node program
# provides one by translating memory tool calls into REST API requests.
stdenvNoCC.mkDerivation {
  pname = "supermemory-mcp";
  version = "0.1.0";

  src = ../mcp;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm644 server.mjs "$out/lib/supermemory-mcp/server.mjs"
    makeWrapper ${lib.getExe nodejs} "$out/bin/supermemory-mcp" \
      --add-flags "$out/lib/supermemory-mcp/server.mjs"
    runHook postInstall
  '';

  meta = {
    description = "MCP endpoint for a self-hosted Supermemory server";
    homepage = "https://github.com/Fractal-Tess/supermemory-flake";
    license = lib.licenses.mit;
    mainProgram = "supermemory-mcp";
    platforms = lib.platforms.linux;
  };
}
