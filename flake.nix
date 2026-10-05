{
  description = "Self-hosted Supermemory server packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # The server is unfree, so allow exactly this package rather than
      # asking every consumer to set allowUnfree.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "supermemory-server";
        };
      packagesFor = system: {
        supermemory-server = (pkgsFor system).callPackage ./packages/supermemory-server.nix { };
        supermemory-mcp = (pkgsFor system).callPackage ./packages/supermemory-mcp.nix { };
      };
    in
    {
      packages = forAllSystems (
        system: packagesFor system // { default = (packagesFor system).supermemory-server; }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.supermemory-server}/bin/supermemory-server";
          meta.description = "Run the Supermemory server";
        };
      });

      checks = forAllSystems (system: {
        inherit (self.packages.${system}) supermemory-server supermemory-mcp;
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      overlays.default = final: _previous: {
        supermemory-server = final.callPackage ./packages/supermemory-server.nix { };
        supermemory-mcp = final.callPackage ./packages/supermemory-mcp.nix { };
      };

      nixosModules.default = import ./modules/nixos.nix { inherit self; };
      homeManagerModules.default = import ./modules/home-manager.nix { inherit self; };
    };
}
