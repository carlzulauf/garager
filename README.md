# Garager

Opens a secure websocket connection to a control server, so your garage door can be opened from anywhere (that can access your control server) with low latency (connection is already open).

Garager runs on a Raspberry Pi wired to a relay across the garage door opener's button terminals. The Pi runs NixOS, built from this repository as a ready-to-boot SD card image with your wifi network, admin user and SSH key already configured.

## Raspberry Pi setup

Supported boards: Raspberry Pi 3, 4 and Zero 2 W (anything that runs 64-bit ARM). The Pi 5 is not supported by the generic NixOS image.

You need a Linux machine with [Nix](https://nixos.org/download) installed (flakes enabled) and an SD card reader. All commands run from this repository's root.

### 1. Allow your machine to build Raspberry Pi software (one time)

The Pi is an ARM (aarch64) computer, so your machine needs emulation to build for it. On NixOS, add this to your system configuration and run `sudo nixos-rebuild switch`:

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

On other distros, install `qemu-user-static` with binfmt support and add `extra-platforms = aarch64-linux` to `/etc/nix/nix.conf`. The `image` command below checks for this and tells you if it's missing.

### 2. Build and flash

```sh
nix run .#pi -- setup              # asks for wifi, admin user, SSH key, control server; writes config/pi.json
nix run .#pi -- image              # builds the SD card image
nix run .#pi -- flash /dev/sdX     # writes it to the SD card (asks before erasing)
```

Run `lsblk` to find your SD card's device (or run `flash` with no device to list disks). Use the whole disk, like `/dev/sdb` or `/dev/mmcblk0`, not a partition.

The first `image` build takes a while, because some packages are compiled under emulation. Later builds are fast.

`config/pi.json` is gitignored. It holds the wifi password in plaintext, so you can check it and fix typos by editing the file, along with other machine-specific settings. The password also ends up readable on the SD card, so treat the card and any built image as you would the password itself.

`setup` also creates an admin user, which logs in over SSH with your key and uses its password for `sudo`. Only a hash of the admin password is stored. Root can't log in over SSH. To change the admin user or password later, run `nix run .#pi -- admin` and then `deploy`.

The admin user's shell is fish, with direnv (and nix-direnv), podman, and common command-line tools installed. [dotbox](https://github.com/carlzulauf/dotbox) is built into the image at the version pinned in `flake.lock`. On first boot, before SSH starts, it's copied to `~/projects/dotbox` and its dotfiles are installed. Once the Pi is online, that copy is connected to GitHub so `git pull` works. To build with a newer dotbox, run `nix flake update dotbox`. Garager itself is cloned from GitHub into `~/projects/garager` once the Pi is online.

### 3. Boot and authorize the device

Put the card in the Pi and power it on. After a minute or two it joins your wifi and is reachable as `garager.local` (or whatever hostname you chose).

On first start, garager generates a keypair on the Pi. Print the public key and add it to the control server's `config/authorized_devices.yml` under the device name you chose during setup:

```sh
nix run .#pi -- pubkey
```

To reuse the keypair from an existing garager install instead, copy that install's `config/production.yaml` into this repository's `config/` directory and run `deploy`. It's copied to the Pi and replaces the generated one.

Check it's working:

```sh
nix run .#pi -- logs
```

### Updating the Pi

After pulling changes or editing `config/pi.json`, push them to the running Pi:

```sh
nix run .#pi -- deploy
```

`pubkey` and `deploy` ask for the admin password, which they use for `sudo` on the Pi.

`pubkey`, `logs` and `deploy` connect to `<hostname>.local` as the admin user. Pass a host or IP address as an extra argument to override it, e.g. `nix run .#pi -- logs 192.168.1.50`, or `user@host` to log in as a different user. You can also `ssh <admin>@garager.local` directly.

A Pi set up before admin users existed only accepts root logins. Add the admin user with `nix run .#pi -- admin`, then deploy once as root with `nix run .#pi -- deploy root@garager.local`. From then on, root SSH logins are disabled.

### Wiring

The relay's control input goes to GPIO17 (physical pin 11), which is the default. The relay is active-low: garager pulls the line low for half a second to "press" the button. To use a different line, change it during `setup` or edit `gpioLine` in `config/pi.json` and redeploy.

### Camera

If you choose a camera during setup, the Pi captures a snapshot from `/dev/video0` every 10 seconds and sends it to the control server. With no camera, the server shows a placeholder image.

- `usb`: USB (UVC) webcams.
- `module`: the Raspberry Pi camera module v1 (OV5647) or v2 (IMX219), using the GPU firmware's legacy camera stack. The v3 and HQ camera modules need the newer libcamera stack, which isn't supported.

The `module` option changes the firmware's `config.txt`, which only `image` writes. `deploy` doesn't update it. To switch a running Pi to the camera module without reflashing, set `"camera": "module"` in `config/pi.json`, run `deploy`, and then:

```sh
ssh <admin>@garager.local
sudo -i
mount /dev/disk/by-label/FIRMWARE /mnt
printf '\n[all]\nstart_x=1\ngpu_mem=128\n' >> /mnt/config.txt
umount /mnt && reboot
```

## Using the NixOS module elsewhere

The flake exports `nixosModules.default`, which adds `services.garager`:

```nix
{
  imports = [ garager.nixosModules.default ];

  services.garager = {
    enable = true;
    serverUri = "wss://example.com/cable";
    deviceId = "garage";
    gpioLine = "GPIO17";
    camera.enable = false;
  };
}
```

The device config, including its private key, lives in `/var/lib/garager/production.yaml`.

## Development

```sh
nix develop            # or `direnv allow` with `use flake` in .envrc
bundle install
bundle exec rspec
bin/client             # runs against config/development.yaml with a fake garage
```

`nix/tests/fake_cable.rb` is a minimal stand-in for the control server (`bundle exec ruby nix/tests/fake_cable.rb`). With it running, `bin/client` connects to it using the default development config.

After changing the `Gemfile`, run `bundle lock` and then `bundix` to regenerate `gemset.nix`, which the Nix package uses.

`nix flake check` builds the package and boots a VM that runs the NixOS module against the fake control server.

Config values can be overridden with environment variables: `GARAGER_SERVER_URI`, `GARAGER_DEVICE_ID`, `GARAGER_CAPTURE_PATH`, `GARAGER_CONFIG_DIR`, `GARAGER_GPIO_LINE` and `GARAGER_DEBUG`.
