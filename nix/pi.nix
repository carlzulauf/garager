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
  dotbox,
  ...
}:

let
  s = piSettings;
  # false, "usb" or "module"
  cameraModule = s.camera == "module";
  adminHome = config.users.users.${s.adminUser}.home;
  dotboxDir = "${adminHome}/projects/dotbox";

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
      "gpio"
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

  # dotbox comes from the flake input pinned in flake.lock, so the dotfiles are
  # in place before sshd starts, even with no internet. Runs once, when
  # ~/projects/dotbox doesn't exist yet.
  systemd.services.dotbox-install = {
    description = "Install dotbox dotfiles for ${s.adminUser}";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    unitConfig.ConditionPathExists = "!${dotboxDir}";
    path = with pkgs; [
      coreutils
      git
      ruby_4_0
    ];
    serviceConfig = {
      Type = "oneshot";
      User = s.adminUser;
      Group = "users";
      # Don't hold up sshd for long if something goes wrong
      TimeoutStartSec = "2min";
    };
    script = ''
      mkdir -p ${adminHome}/projects
      cp -r ${dotbox} ${dotboxDir}.tmp
      chmod -R u+w ${dotboxDir}.tmp
      mv ${dotboxDir}.tmp ${dotboxDir}
      git -C ${dotboxDir} init -q -b main
      git -C ${dotboxDir} remote add origin https://github.com/carlzulauf/dotbox.git
      # The hooks are for GNOME desktops
      ruby ${dotboxDir}/bin/install_dotfiles --yes --skip-hooks
    '';
  };

  # Turns the copy above into a git checkout of the pinned commit, once the
  # network is up. The files already match that commit, so it ends up clean.
  # Retries until it succeeds, and skips once anything has fetched.
  systemd.services.dotbox-git = {
    description = "Connect ~/projects/dotbox to GitHub";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "dotbox-install.service"
    ];
    unitConfig = {
      ConditionPathExists = [
        "${dotboxDir}/.git"
        "!${dotboxDir}/.git/FETCH_HEAD"
      ];
    };
    startLimitIntervalSec = 0;
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      User = s.adminUser;
      Group = "users";
      WorkingDirectory = dotboxDir;
      Restart = "on-failure";
      RestartSec = 30;
    };
    script = ''
      git fetch origin
      git reset -q ${dotbox.rev}
      git branch --set-upstream-to=origin/main main
    '';
  };

  # A checkout of this repo, for working on garager from the Pi. Retries until
  # the network is up, and does nothing once ~/projects/garager exists.
  systemd.services.garager-clone = {
    description = "Clone garager into ~/projects/garager";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!${adminHome}/projects/garager";
    startLimitIntervalSec = 0;
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      User = s.adminUser;
      Group = "users";
      Restart = "on-failure";
      RestartSec = 30;
    };
    script = ''
      mkdir -p ${adminHome}/projects
      git clone https://github.com/carlzulauf/garager.git ${adminHome}/projects/garager
    '';
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
  # On 6.18, bcm2835-v4l2's frame transfers fail ("vchiq_bulk_receive failed -22")
  # and captures never get a frame. 6.12 (LTS) still works.
  boot.kernelPackages = lib.mkIf cameraModule pkgs.linuxPackages_6_12;

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
