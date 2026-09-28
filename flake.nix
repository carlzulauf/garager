{
  description = "garager - remote garage door controller";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            ruby_4_0
            git
            pkg-config
            libyaml.dev
            openssl.dev
          ];

          shellHook = ''
            export GEM_HOME="$HOME/.local/share/gems/garager"
            export PATH="$GEM_HOME/bin:$PATH"
            export BUNDLE_PATH="$GEM_HOME"

            echo "### garager dev shell ###"
            echo "Ruby ${pkgs.ruby_4_0.version}"
            echo ""
          '';
        };
      });
}
