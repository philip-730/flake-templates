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
        # Next.js standalone build
        # Requires next.config output: "standalone" to be set.
        #
        # Get npmDepsHash:
        #   nix build .#image --impure  (with npmDepsHash = lib.fakeHash)
        #   then paste the hash from the error.
        # ------------------------------------------------------------------ #
        frontend = pkgs.buildNpmPackage {
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

          NEXT_TELEMETRY_DISABLED = "1";

          preBuild = ''
            export NODE_ENV=production
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r .next/standalone/. $out/
            mkdir -p $out/.next
            cp -r .next/static $out/.next/static
            cp -r public $out/public
            runHook postInstall
          '';
        };

        # ------------------------------------------------------------------ #
        # OCI image
        # ------------------------------------------------------------------ #
        image = pkgs.dockerTools.streamLayeredImage {
          name = "my-project";
          tag = "latest";
          contents = [ pkgs.cacert pkgs.nodejs_24 frontend ];
          config = {
            Cmd = [ "${pkgs.nodejs_24}/bin/node" "${frontend}/server.js" ];
            WorkingDir = "${frontend}";
            Env = [
              "NODE_ENV=production"
              "HOSTNAME=0.0.0.0"
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
          inherit image frontend;
          default = frontend;
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
