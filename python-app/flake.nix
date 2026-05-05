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
        # Python venv via uv2nix
        # workspaceRoot should contain pyproject.toml + uv.lock
        # ------------------------------------------------------------------ #
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.;
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

        venv = pythonSet.mkVirtualEnv "my-project-env" workspace.deps.default;

        # Include dev deps (e.g. pytest, ruff) — used in the dev shell.
        devVenv = pythonSet.mkVirtualEnv "my-project-dev-env" workspace.deps.all;

        # ------------------------------------------------------------------ #
        # OCI image
        # ------------------------------------------------------------------ #
        image = pkgs.dockerTools.streamLayeredImage {
          name = "my-project";
          tag = "latest";
          contents = [ venv pkgs.cacert ];
          config = {
            # Adjust entrypoint to suit your app (uvicorn, python -m, etc.)
            Cmd = [ "uvicorn" "app.main:app" "--host" "0.0.0.0" "--port" "8000" ];
            WorkingDir = "/app";
            Env = [
              "PATH=${venv}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            ExposedPorts."8000/tcp" = { };
          };
        };

      in
      {
        packages = {
          inherit image;
          default = venv;
        };

        devShells = {
          default = pkgs.mkShell {
            name = "my-project";
            packages = [
              devVenv
              pkgs.python313
              pkgs.uv
              pkgs.just
            ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              echo "my-project dev shell"
              echo "  python $(python3 --version)  |  uv $(uv --version)"
            '';
          };

          # Use this shell to initialise a new project before uv.lock exists.
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
