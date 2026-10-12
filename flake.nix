{
  description = "garager - remote garage door controller";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Machine-specific Pi settings live in config/pi.json (gitignored), which
      # `nix run .#pi -- setup` creates. Flakes can't see untracked files, so the
      # pi helper passes its path in GARAGER_PI_SETTINGS and builds with --impure.
      # Pure evaluation falls back to placeholders so `nix flake check` works.
      piSettingsPath = builtins.getEnv "GARAGER_PI_SETTINGS";
      piSettings =
        if piSettingsPath != "" then
          builtins.fromJSON (builtins.readFile piSettingsPath)
        else
          {
            hostname = "garager";
            wifiSsid = "example";
            wifiPassword = "example-password";
            sshKeys = [ ];
            serverUri = "wss://example.com/cable";
            deviceId = "garager";
            timeZone = "UTC";
            gpioLine = "GPIO17";
            camera = false;
          };
    in
    {
      nixosModules.default = import ./nix/module.nix;

      nixosConfigurations.pi = nixpkgs.lib.nixosSystem {
        modules = [
          ./nix/pi.nix
          { _module.args.piSettings = piSettings; }
        ];
      };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        pi = pkgs.writeShellApplication {
          name = "garager-pi";
          runtimeInputs = with pkgs; [
            coreutils
            findutils
            git
            gnused
            jq
            nixos-rebuild
            openssh
            util-linux
            zstd
          ];
          text = builtins.readFile ./nix/pi.sh;
        };
      in {
        packages = {
          default = pkgs.callPackage ./nix/package.nix { };
          inherit pi;
        };

        apps.pi = {
          type = "app";
          program = pkgs.lib.getExe pi;
        };

        checks = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          module = import ./nix/tests/module.nix {
            inherit pkgs;
            module = self.nixosModules.default;
          };
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            ruby_4_0
            bundix
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
