# NixOS system for a Raspberry Pi 3, 4 or Zero 2 W running garager.
#
# Machine-specific values (wifi, ssh keys, server) come from `piSettings`,
# which the flake reads from config/pi.json. Create that file with
# `nix run .#pi -- setup`.
{
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
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = s.sshKeys;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "root" ];
  };

  # Keep the SD card from filling up with old generations
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  boot.loader.generic-extlinux-compatible.configurationLimit = 5;

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
