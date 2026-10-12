{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.garager;
  captureDir = "/run/garager-camera";
in
{
  options.services.garager = {
    enable = lib.mkEnableOption "garager, the garage door control client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The garager package to run.";
    };

    environment = lib.mkOption {
      type = lib.types.enum [
        "production"
        "development"
      ];
      default = "production";
      description = ''
        `production` toggles the real garage door through GPIO.
        `development` uses a fake garage that only logs toggles.
      '';
    };

    serverUri = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "wss://example.com/cable";
      description = "Websocket URI of the control server. Overrides `server_uri` in the config file.";
    };

    deviceId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Device name reported to the control server. Overrides `device_id` in the config file.";
    };

    gpioLine = lib.mkOption {
      type = lib.types.str;
      default = "GPIO17";
      description = "Name of the GPIO line wired to the relay. GPIO17 is physical pin 11.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log at debug level.";
    };

    camera = {
      enable = lib.mkEnableOption "periodic snapshots from a V4L2 camera, sent to the control server";

      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/video0";
        description = "V4L2 video device to capture from.";
      };

      interval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "Seconds between snapshots.";
      };

      resolution = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "1024x768";
        description = "Capture resolution. Uses the camera default when null.";
      };

      warmupFrames = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 0;
        description = "Frames to discard before each snapshot, for cameras whose first frames are badly exposed.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.garager = {
      isSystemUser = true;
      group = "garager";
      extraGroups = [
        "gpio"
        "video"
      ];
      home = "/var/lib/garager";
    };
    users.groups.garager = { };
    users.groups.gpio = { };

    services.udev.extraRules = ''
      SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
    '';

    systemd.services.garager = {
      description = "Garager garage door control client";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.libgpiod ];

      environment = {
        GARAGER_ENV = cfg.environment;
        GARAGER_CONFIG_DIR = "/var/lib/garager";
        GARAGER_GPIO_LINE = cfg.gpioLine;
      }
      // lib.optionalAttrs (cfg.serverUri != null) { GARAGER_SERVER_URI = cfg.serverUri; }
      // lib.optionalAttrs (cfg.deviceId != null) { GARAGER_DEVICE_ID = cfg.deviceId; }
      // lib.optionalAttrs cfg.debug { GARAGER_DEBUG = "1"; }
      // lib.optionalAttrs cfg.camera.enable { GARAGER_CAPTURE_PATH = "${captureDir}/capture.jpg"; };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        User = "garager";
        Group = "garager";
        # The config file (with the device's private key) is generated here on first start
        StateDirectory = "garager";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Restart = "always";
        RestartSec = 5;
      }
      // lib.optionalAttrs (cfg.environment == "production") {
        # Idle the relay line with a pull-up, like bin/garage_toggle leaves it,
        # so the relay's LED is off from boot. "-": start garager regardless.
        ExecStartPre = "-${lib.getExe' pkgs.libgpiod "gpioget"} --consumer garager --bias pull-up --numeric ${lib.escapeShellArg cfg.gpioLine}";
      };
    };

    systemd.services.garager-camera = lib.mkIf cfg.camera.enable {
      description = "Garager camera snapshots";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.ffmpeg-headless ];

      script = ''
        while true; do
          ffmpeg -loglevel error -f v4l2 \
            ${lib.optionalString (cfg.camera.resolution != null) "-video_size ${cfg.camera.resolution}"} \
            -i ${lib.escapeShellArg cfg.camera.device} \
            ${lib.optionalString (cfg.camera.warmupFrames > 0) "-vf \"select='gte(n,${toString cfg.camera.warmupFrames})'\""} \
            -frames:v 1 -update 1 -y ${captureDir}/capture.tmp.jpg \
            && mv ${captureDir}/capture.tmp.jpg ${captureDir}/capture.jpg
          sleep ${toString cfg.camera.interval}
        done
      '';

      serviceConfig = {
        User = "garager";
        Group = "garager";
        RuntimeDirectory = "garager-camera";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
