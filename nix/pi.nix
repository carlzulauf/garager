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
    networks.${s.wifiSsid}.pskRaw = s.wifiPskRaw;
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

  environment.systemPackages = with pkgs; [
    libgpiod
    v4l-utils
  ];

  services.garager = {
    enable = true;
    serverUri = s.serverUri;
    deviceId = s.deviceId;
    gpioLine = s.gpioLine;
    camera.enable = s.camera;
  };
}
