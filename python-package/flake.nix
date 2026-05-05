{
  description = "my-package";

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

        # ------------------------------------------------------------------ #
        # Editable overlay — local packages are mounted from source so
        # changes are reflected immediately without rebuilding.
        # REPO_ROOT is set in the shellHook below.
        # ------------------------------------------------------------------ #
        editableOverlay = workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };

        editablePythonSet = pythonSet.overrideScope editableOverlay;

        # Editable venv with all dev deps (e.g. pytest, ruff).
        editableVenv = editablePythonSet.mkVirtualEnv "my-package-dev-env"
          workspace.deps.all;

        # Non-editable venv — used for the default (built) package output.
        venv = pythonSet.mkVirtualEnv "my-package-env" workspace.deps.default;

      in
      {
        packages.default = venv;

        devShells = {
          default = pkgs.mkShell {
            name = "my-package";
            packages = [ editableVenv pkgs.uv pkgs.just ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = editablePythonSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };

          # Use this shell to initialise the project before uv.lock exists.
          # nix develop .#bootstrap → uv init → uv add <deps> → uv lock
          # Then switch to `nix develop` (the default shell).
          bootstrap = pkgs.mkShell {
            name = "my-package-bootstrap";
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
