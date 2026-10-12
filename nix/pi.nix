# NixOS system for a Raspberry Pi 3, 4 or Zero 2 W running garager.
#
# Machine-specific values (wifi, ssh keys, server) come from `piSettings`,
# which the flake reads from config/pi.json. Create that file with
# `nix run .#pi -- setup`.
{
  config,
  lib,
  pkgs,
  modulesPath,
  piSettings,
  ...
}:

let
  s = piSettings;
  # false, "usb" or "module"
  cameraModule = s.camera == "module";
  # Same nix-direnv as carlzulauf/dotbox nix/includes/defaults.nix. 3.2.0
  # misbehaves when several tmux windows load the same flake-based .envrc at
  # once, so stay on 3.1.2. resholve builds nix-direnv in two stages, so the
  # older source has to go into the inner (unresholved) derivation too.
  useNixDirenv312 =
    drv:
    drv.overrideAttrs (_: {
      version = "3.1.2";
      src = pkgs.fetchFromGitHub {
        owner = "nix-community";
        repo = "nix-direnv";
        rev = "3.1.2";
        hash = "sha256-3qT5mSqHi+0cskdoOGPVbuSzkoWtwOHBVXUOL84dAM8=";
      };
    });
  nixDirenv = pkgs.nix-direnv.override { nix = config.nix.package; };
  nixDirenvPinned = (useNixDirenv312 nixDirenv).overrideAttrs (_: {
    src = useNixDirenv312 nixDirenv.unresholved;
  });
in
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    ./module.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Set once when the image is first built. Do not change on upgrades.
  system.stateVersion = "26.11";

  image.baseName = "garager-${s.hostname}";

  hardware.enableRedistributableFirmware = true;
  zramSwap.enable = true;
  documentation.enable = false;

  networking.hostName = s.hostname;
  networking.wireless = {
    enable = true;
    networks.${s.wifiSsid}.psk = s.wifiPassword;
  };

  time.timeZone = s.timeZone;

  # Reachable as <hostname>.local
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Log in as the admin user and use sudo. config/pi.json is the source of
  # truth for accounts, so changing the password there and deploying applies it.
  users.mutableUsers = false;
  users.users.${s.adminUser} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "systemd-journal"
    ];
    hashedPassword = s.adminPasswordHash;
    openssh.authorizedKeys.keys = s.sshKeys;
    shell = pkgs.fish;
  };

  programs.fish.enable = true;
  # Leave these to the dotbox fish config
  programs.fish.shellAliases = {
    l = null;
    ll = null;
    ls = null;
  };

  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    nix-direnv = {
      enable = true;
      package = nixDirenvPinned;
    };
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Lets deploy copy builds to the Pi as the admin user
    trusted-users = [
      "root"
      "@wheel"
    ];
  };

  # Keep the SD card from filling up with old generations
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  boot.loader.generic-extlinux-compatible.configurationLimit = 5;

  services.resolved = {
    enable = true;
    # Avahi already answers for <hostname>.local
    settings.Resolve.MulticastDNS = false;
  };

  virtualisation.podman.enable = true;

  # The camera module runs on the GPU firmware's legacy camera stack, which the
  # bcm2835-v4l2 driver exposes as an ordinary V4L2 device at /dev/video0.
  # Only v1 (OV5647) and v2 (IMX219) modules are supported this way.
  sdImage.populateFirmwareCommands = lib.mkIf cameraModule (
    lib.mkAfter ''
      # Copied read-only from the store by sd-image-aarch64.nix
      chmod u+w firmware/config.txt
      cat >>firmware/config.txt <<'EOF'

      [all]
      start_x=1
      gpu_mem=128
      EOF
    ''
  );
  boot.kernelModules = lib.optional cameraModule "bcm2835-v4l2";

  environment.systemPackages = with pkgs; [
    libgpiod
    v4l-utils

    nano
    micro
    git
    tmux
    eza
    file
    fzf
    starship
    wget
    curl
    dig
    dysk
    ncdu
    btop
    htop
    fastfetch
    jq
    yq
    ruby_4_0
  ];

  services.garager = {
    enable = true;
    serverUri = s.serverUri;
    deviceId = s.deviceId;
    gpioLine = s.gpioLine;
    camera.enable = s.camera != false;
    # The first frames are dark while the module's auto exposure settles
    camera.warmupFrames = lib.mkIf cameraModule 30;
  };
}
