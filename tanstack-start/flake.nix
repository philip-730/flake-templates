{
  description = "my-project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};

        # ------------------------------------------------------------------ #
        # TanStack Start build (node-server preset)
        # Requires app.config.ts to set:
        #   server: { preset: "node-server" }
        #
        # Get npmDepsHash:
        #   nix build .#image --impure  (with npmDepsHash = lib.fakeHash)
        #   then paste the hash from the error.
        # ------------------------------------------------------------------ #
        app = pkgs.buildNpmPackage {
          pname = "my-project";
          version = "0.1.0";
          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let name = baseNameOf (toString path);
              in !(lib.hasPrefix ".env" name) && name != "node_modules";
          };

          npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          # npmDepsHash = pkgs.lib.fakeHash;

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r .output/. $out/
            runHook postInstall
          '';
        };

        # ------------------------------------------------------------------ #
        # OCI image
        # ------------------------------------------------------------------ #
        image = pkgs.dockerTools.streamLayeredImage {
          name = "my-project";
          tag = "latest";
          contents = [ pkgs.cacert pkgs.nodejs_24 app ];
          config = {
            Cmd = [ "${pkgs.nodejs_24}/bin/node" "${app}/server/index.mjs" ];
            WorkingDir = "${app}";
            Env = [
              "NODE_ENV=production"
              "PORT=3000"
              "NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            ExposedPorts."3000/tcp" = { };
          };
        };

      in
      {
        packages = {
          inherit image app;
          default = app;
        };

        devShells.default = pkgs.mkShell {
          name = "my-project";
          packages = with pkgs; [ nodejs_24 just ];
          shellHook = ''
            echo "my-project dev shell"
            echo "  node $(node --version)  |  npm $(npm --version)"
          '';
        };
      }
    );
}
