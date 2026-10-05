{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "supermemory-server";
  version = "0.0.8";

  sources = {
    x86_64-linux = {
      asset = "supermemory-server-linux-x64";
      hash = "sha256-h/MkM9AXm+gLudihuvusZa9BKDJDQqJ+y4vRp3tVBvM=";
    };
    aarch64-linux = {
      asset = "supermemory-server-linux-arm64";
      hash = "sha256-7rnmKov1lka9eZoF0aKYG5RUE6A2QMOjn08metLSvzc=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/supermemoryai/supermemory/releases/download/server-v${version}/${source.asset}";
    inherit (source) hash;
  };

  dontUnpack = true;
  # The binary is a Bun standalone executable: the app is appended after the
  # ELF image, so stripping it would cut the payload off.
  dontStrip = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/supermemory-server"
    runHook postInstall
  '';

  meta = {
    description = "Self-hosted Supermemory server: memory API, extraction, and hybrid search in one binary";
    homepage = "https://supermemory.ai/docs/self-hosting/overview";
    changelog = "https://github.com/supermemoryai/supermemory/releases/tag/server-v${version}";
    downloadPage = "https://github.com/supermemoryai/supermemory/releases";
    # The server binary is built from a non-public codebase.
    license = lib.licenses.unfree;
    mainProgram = "supermemory-server";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames sources;
  };
}
