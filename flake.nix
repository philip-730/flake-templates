{
  description = "Personal Nix flake templates";

  outputs = { self, ... }: {
    templates = {
      python-app = {
        path = ./python-app;
        description = "Python application with uv2nix, dev shell, and OCI image";
      };

      python-package = {
        path = ./python-package;
        description = "Python library with uv2nix and editable installs dev shell";
      };

      nextjs = {
        path = ./nextjs;
        description = "Next.js standalone build with OCI image and dev shell";
      };

      fullstack = {
        path = ./fullstack;
        description = "Full-stack FastAPI + Next.js with OCI images and composed dev shells";
      };

      tanstack-start = {
        path = ./tanstack-start;
        description = "TanStack Start node-server build with OCI image and dev shell";
      };
    };
  };
}
