{
  description = "Flake with Talos and K8S tools";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:

      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in {

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = (with pkgs; [
            # General dependencies
            lazygit
            sops
            gnupg

            # Kubernetes dependencies
            kubectl
            fluxcd
            talosctl
          ]) ++ (with pkgs.nodePackages; [ markdownlint-cli ]);

        };
      });
}
