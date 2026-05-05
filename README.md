# flake-templates

Personal Nix flake templates.

## Usage

```bash
nix flake init -t github:philip-730/flake-templates#<template>
```

Then find-and-replace `my-project` with your project name:

```bash
sed -i 's/my-project/your-project-name/g' flake.nix
```

## Templates

### `python-app`

Python application with [uv2nix](https://github.com/pyproject-nix/uv2nix), a dev shell, and an OCI image.

```bash
nix flake init -t github:philip-730/flake-templates#python-app
nix develop .#bootstrap   # uv + python only, no uv.lock needed yet
uv init                   # creates pyproject.toml (UV_NO_SYNC skips .venv creation)
uv add <deps>             # uv.lock is created here
exit                      # leave bootstrap shell
nix develop               # full dev shell via uv2nix
```

```bash
nix build .#image         # build OCI image
```

### `python-package`

Python library with [uv2nix](https://github.com/pyproject-nix/uv2nix) and editable installs.
Source changes are reflected immediately in the dev shell without rebuilding.

```bash
nix flake init -t github:philip-730/flake-templates#python-package
nix develop .#bootstrap   # uv + python only, no uv.lock needed yet
uv init                   # creates pyproject.toml
uv add <deps>             # uv.lock is created here
exit                      # leave bootstrap shell
nix develop               # editable dev shell via uv2nix
```

### `nextjs`

Next.js standalone build with an OCI image and dev shell. Requires `output: "standalone"` in `next.config`.

```bash
nix flake init -t github:philip-730/flake-templates#nextjs
# replace npmDepsHash with pkgs.lib.fakeHash, run nix build .#image,
# then paste the correct hash from the error output
nix develop
nix build .#image
```

### `tanstack-start`

TanStack Start with node-server preset, OCI image, and dev shell.
Requires `server: { preset: "node-server" }` in `app.config.ts`.

```bash
nix flake init -t github:philip-730/flake-templates#tanstack-start
# replace npmDepsHash with pkgs.lib.fakeHash, run nix build .#image,
# then paste the correct hash from the error output
nix develop
nix build .#image
```

### `fullstack`

FastAPI backend + Next.js frontend with OCI images and composed dev shells.
Expects source laid out as `./backend` (Python) and `./frontend` (Next.js).

```bash
nix flake init -t github:philip-730/flake-templates#fullstack
nix develop .#bootstrap   # scaffold backend: uv init --no-workspace && uv add <deps>
exit                      # leave bootstrap shell
nix develop               # full stack shell
nix develop .#backend
nix develop .#frontend
nix build .#backend-image
nix build .#frontend-image
```
