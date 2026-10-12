{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:

let
  pname = "supermemory-server";
  version = "0.0.9";

  sources = {
    x86_64-linux = {
      asset = "supermemory-server-linux-x64";
      hash = "sha256-15h+y/KwJMbenRZ77Lz8qrzkRxabQdb1bbhvh9UYeYQ=";
    };
    aarch64-linux = {
      asset = "supermemory-server-linux-arm64";
      hash = "sha256-t4m+Fs1xkrPAjogjlsCpS6Mw6kZ9Wn+xs5rDaEq/U3Q=";
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

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/libexec/supermemory-server"
    # At first start the server unpacks a prebuilt onnxruntime into its data
    # directory for local embeddings. That library looks up libstdc++ at run
    # time; without it the server falls back to a WebAssembly build that grows
    # to tens of gigabytes of memory.
    makeWrapper "$out/libexec/supermemory-server" "$out/bin/supermemory-server" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}
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
