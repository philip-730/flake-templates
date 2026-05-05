{
  description = "my-project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, flake-utils, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};

        # ------------------------------------------------------------------ #
        # Backend — Python venv via uv2nix
        # ./backend must contain pyproject.toml + uv.lock
        # ------------------------------------------------------------------ #
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./backend;
        };

        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

        pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
          python = pkgs.python313;
        }).overrideScope (lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          overlay
        ]);

        backendVenv = pythonSet.mkVirtualEnv "my-project-backend-env"
          workspace.deps.default;

        backendDevVenv = pythonSet.mkVirtualEnv "my-project-backend-dev-env"
          workspace.deps.all;

        # ------------------------------------------------------------------ #
        # Frontend — Next.js standalone build
        # ./frontend must contain package.json + package-lock.json
        # next.config must set output: "standalone"
        #
        # Get npmDepsHash:
        #   nix build .#frontend-image --impure (with npmDepsHash = lib.fakeHash)
        #   then paste the hash from the error.
        # ------------------------------------------------------------------ #
        frontendBuild = pkgs.buildNpmPackage {
          pname = "my-project-frontend";
          version = "0.1.0";
          src = lib.cleanSourceWith {
            src = ./frontend;
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
        # OCI images
        # ------------------------------------------------------------------ #
        backendImage = pkgs.dockerTools.streamLayeredImage {
          name = "my-project-backend";
          tag = "latest";
          contents = [ backendVenv pkgs.cacert ];
          config = {
            Cmd = [ "uvicorn" "app.main:app" "--host" "0.0.0.0" "--port" "8000" "--proxy-headers" ];
            WorkingDir = "/app";
            Env = [
              "PATH=${backendVenv}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            ExposedPorts."8000/tcp" = { };
          };
        };

        frontendImage = pkgs.dockerTools.streamLayeredImage {
          name = "my-project-frontend";
          tag = "latest";
          contents = [ pkgs.cacert pkgs.nodejs_24 frontendBuild ];
          config = {
            Cmd = [ "${pkgs.nodejs_24}/bin/node" "${frontendBuild}/server.js" ];
            WorkingDir = "${frontendBuild}";
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

        # ------------------------------------------------------------------ #
        # Dev shell package groups
        # ------------------------------------------------------------------ #
        backendPackages = [
          backendDevVenv
          pkgs.python313
          pkgs.uv
          pkgs.just
        ];

        frontendPackages = with pkgs; [ nodejs_24 just ];

        # Optional: k8s tooling — uncomment if deploying to kubernetes
        # k8sPackages = with pkgs; [ kubectl kubernetes-helm k9s skopeo ];

      in
      {
        packages = {
          backend-image = backendImage;
          frontend-image = frontendImage;
        };

        devShells = {
          default = pkgs.mkShell {
            name = "my-project";
            packages = backendPackages ++ frontendPackages;
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              echo "my-project dev shell"
              echo "  node $(node --version)  |  python $(python3 --version)"
            '';
          };

          backend = pkgs.mkShell {
            name = "my-project-backend";
            packages = backendPackages;
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
            '';
          };

          frontend = pkgs.mkShell {
            name = "my-project-frontend";
            packages = frontendPackages;
          };

          # Use this shell to initialise the backend before uv.lock exists.
          # nix develop .#bootstrap → uv init → uv add <deps> → uv lock
          # Then switch to `nix develop` (the default shell).
          bootstrap = pkgs.mkShell {
            name = "my-project-bootstrap";
            packages = [ pkgs.uv pkgs.python313 ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
            '';
          };
        };
      }
    );
}
