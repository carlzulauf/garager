# Helper for building, flashing and deploying the garager Raspberry Pi image.
# Run via `nix run .#pi -- <command>` from the garager checkout.

usage() {
  cat <<'EOF'
Usage: nix run .#pi -- <command>

Commands:
  setup            Create config/pi.json (wifi, ssh key, control server)
  image            Build the SD card image
  flash <device>   Write the image to an SD card, e.g. /dev/sdb
  deploy [host]    Push the current config/code to a running Pi
  pubkey [host]    Print the Pi's public key, to authorize it on the control server
  logs [host]      Follow the garager service logs on the Pi

host defaults to <hostname>.local from config/pi.json
EOF
}

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$root" || ! -f "$root/flake.nix" ]]; then
  echo "Run this from inside the garager git checkout." >&2
  exit 1
fi
settings="$root/config/pi.json"
export GARAGER_PI_SETTINGS="$settings"

require_settings() {
  if [[ ! -f "$settings" ]]; then
    echo "Missing config/pi.json. Run: nix run .#pi -- setup" >&2
    exit 1
  fi
}

setting() {
  jq -r ".$1" "$settings"
}

target_host() {
  if [[ -n "${1:-}" ]]; then
    echo "$1"
  else
    require_settings
    echo "$(setting hostname).local"
  fi
}

ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply
    echo "${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    echo "$reply"
  fi
}

cmd_setup() {
  if [[ -f "$settings" ]]; then
    read -r -p "config/pi.json already exists. Overwrite? [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]] || exit 0
  fi

  local hostname ssid password key_path server_uri device_id tz camera gpio_line
  hostname="$(ask "Hostname" garager)"
  ssid="$(ask "Wifi network name (SSID)")"
  # Shown as typed, so typos are easy to spot
  password="$(ask "Wifi password")"
  if [[ ! "$password" =~ ^[[:print:]]{8,63}$ ]]; then
    echo "Wifi passwords must be 8-63 printable characters." >&2
    exit 1
  fi

  local default_key=""
  for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -f "$k" ]]; then default_key="$k"; break; fi
  done
  key_path="$(ask "SSH public key for root login" "$default_key")"
  if [[ ! -f "$key_path" ]]; then
    echo "No such file: $key_path" >&2
    exit 1
  fi

  server_uri="$(ask "Control server websocket URI" "wss://example.com/cable")"
  device_id="$(ask "Device name shown on the control server" "$hostname")"
  tz="$(ask "Time zone" "$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)")"
  gpio_line="$(ask "GPIO line wired to the relay" GPIO17)"
  camera="$(ask "Camera: none, usb (webcam), or module (Pi camera module v1/v2)" none)"
  case "$camera" in
    none) camera=false ;;
    usb | module) camera="\"$camera\"" ;;
    *)
      echo "Unknown camera: $camera" >&2
      exit 1
      ;;
  esac

  mkdir -p "$(dirname "$settings")"
  (
    umask 077
    jq -n \
      --arg hostname "$hostname" \
      --arg ssid "$ssid" \
      --arg password "$password" \
      --arg key "$(cat "$key_path")" \
      --arg server_uri "$server_uri" \
      --arg device_id "$device_id" \
      --arg tz "$tz" \
      --arg gpio_line "$gpio_line" \
      --argjson camera "$camera" \
      '{
        hostname: $hostname,
        wifiSsid: $ssid,
        wifiPassword: $password,
        sshKeys: [$key],
        serverUri: $server_uri,
        deviceId: $device_id,
        timeZone: $tz,
        gpioLine: $gpio_line,
        camera: $camera
      }' >"$settings"
  )
  echo "Wrote config/pi.json. Next: nix run .#pi -- image"
}

check_aarch64() {
  if [[ "$(uname -m)" == "aarch64" ]] || [[ -e /proc/sys/fs/binfmt_misc/aarch64-linux ]]; then
    return
  fi
  cat >&2 <<'EOF'
This machine can't build aarch64 (Raspberry Pi) packages yet.

On NixOS, add this to your system configuration and run `nixos-rebuild switch`:

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

On other Linux distros, install qemu-user-static with binfmt support and add
`extra-platforms = aarch64-linux` to /etc/nix/nix.conf.
EOF
  exit 1
}

cmd_image() {
  require_settings
  check_aarch64
  nix build --impure "$root#nixosConfigurations.pi.config.system.build.sdImage" \
    --out-link "$root/result-pi-image" --print-build-logs
  local img
  img="$(find -L "$root/result-pi-image/sd-image" -name '*.img*' | head -n1)"
  echo
  echo "Built $img"
  echo "Next: insert the SD card and run: nix run .#pi -- flash /dev/sdX"
}

cmd_flash() {
  local device="${1:-}"
  if [[ -z "$device" ]]; then
    echo "Usage: nix run .#pi -- flash <device>" >&2
    echo >&2
    lsblk -d -o NAME,SIZE,TRAN,MODEL,RM >&2
    exit 1
  fi
  if [[ ! -b "$device" ]] || [[ "$(lsblk -dno TYPE "$device")" != "disk" ]]; then
    echo "$device is not a whole disk. Pass the disk (e.g. /dev/sdb), not a partition." >&2
    exit 1
  fi
  if lsblk -no MOUNTPOINT "$device" | grep -qE '^/(boot)?$'; then
    echo "$device holds a mounted system partition. Refusing to overwrite it." >&2
    exit 1
  fi

  local img
  img="$(find -L "$root/result-pi-image/sd-image" -name '*.img*' 2>/dev/null | head -n1)"
  if [[ -z "$img" ]]; then
    echo "No image found. Run: nix run .#pi -- image" >&2
    exit 1
  fi

  lsblk -o NAME,SIZE,TRAN,MODEL,MOUNTPOINT "$device"
  echo
  read -r -p "ERASE everything on $device and write $(basename "$img")? Type 'yes': " reply
  [[ "$reply" == "yes" ]] || exit 1

  for part in $(lsblk -lno PATH "$device" | tail -n +2); do
    sudo umount "$part" 2>/dev/null || true
  done

  if [[ "$img" == *.zst ]]; then
    zstd -dc "$img" | sudo dd of="$device" bs=4M conv=fsync status=progress
  else
    sudo dd if="$img" of="$device" bs=4M conv=fsync status=progress
  fi
  sync
  echo
  echo "Done. Put the card in the Pi and power it on. After a minute or two, try:"
  echo "  nix run .#pi -- logs"
}

ssh_opts=(-o StrictHostKeyChecking=accept-new)

cmd_deploy() {
  require_settings
  check_aarch64
  local host
  host="$(target_host "${1:-}")"

  nixos-rebuild switch --impure --flake "$root#pi" \
    --target-host "root@$host" --use-substitutes

  # Reuse an existing device key if there is one in config/
  if [[ -f "$root/config/production.yaml" ]]; then
    echo "Copying config/production.yaml to $host"
    scp "${ssh_opts[@]}" "$root/config/production.yaml" "root@$host:/var/lib/garager/production.yaml"
    ssh "${ssh_opts[@]}" "root@$host" \
      "chown garager:garager /var/lib/garager/production.yaml && chmod 600 /var/lib/garager/production.yaml && systemctl restart garager"
  fi
}

cmd_pubkey() {
  local host
  host="$(target_host "${1:-}")"
  ssh "${ssh_opts[@]}" "root@$host" \
    "sed -n '/^public_key:/,/END PUBLIC KEY/p' /var/lib/garager/production.yaml | sed '1d; s/^  //'"
}

cmd_logs() {
  local host
  host="$(target_host "${1:-}")"
  ssh "${ssh_opts[@]}" "root@$host" journalctl -u garager -u garager-camera -f
}

command="${1:-}"
shift || true
case "$command" in
  setup) cmd_setup "$@" ;;
  image) cmd_image "$@" ;;
  flash) cmd_flash "$@" ;;
  deploy) cmd_deploy "$@" ;;
  pubkey) cmd_pubkey "$@" ;;
  logs) cmd_logs "$@" ;;
  *)
    usage
    [[ -z "$command" || "$command" == "help" || "$command" == "-h" || "$command" == "--help" ]]
    ;;
esac
