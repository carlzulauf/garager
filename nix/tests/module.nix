# Boots a VM running services.garager (with the fake garage) against a fake
# control server, and checks the device registers and handles a toggle.
{ pkgs, module }:

let
  garager = pkgs.callPackage ../package.nix { };
in
pkgs.testers.runNixOSTest {
  name = "garager-module";

  nodes.machine = {
    imports = [ module ];

    systemd.services.fake-cable = {
      wantedBy = [ "multi-user.target" ];
      before = [ "garager.service" ];
      environment.BUNDLE_WITHOUT = "development:test";
      serviceConfig.ExecStart = "${garager.gems.wrappedRuby}/bin/ruby ${./fake_cable.rb} 3333";
    };

    services.garager = {
      enable = true;
      environment = "development";
      serverUri = "ws://localhost:3333/cable";
      deviceId = "vm test";
    };
  };

  testScript = ''
    machine.wait_for_unit("fake-cable.service")
    machine.wait_for_unit("garager.service")
    machine.wait_until_succeeds("journalctl -u fake-cable | grep -q 'received message {\"action\":\"register\"'")
    machine.wait_until_succeeds("journalctl -u fake-cable | grep -q 'update_status_image'")
    machine.wait_until_succeeds("journalctl -u fake-cable | grep -q '\"value\":\"open\"'")
    machine.succeed("test -f /var/lib/garager/development.yaml")
    machine.succeed("stat -c %U /var/lib/garager/development.yaml | grep -q garager")
  '';
}
