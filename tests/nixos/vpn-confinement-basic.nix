{ pkgs, ... }:
{
  name = "vpn-confinement-basic";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-basic";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguardInterface = "wg0";
        dns.servers = [ "10.64.0.1" ];
      };
    };

    networking.wireguard.interfaces.wg0 = {
      privateKeyFile = "/run/wg-test/private.key";
      ips = [
        "10.71.216.231/32"
        "fc00:bbbb:bbbb:bb01::8:d8e6/128"
      ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          persistentKeepalive = 25;
          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
        }
      ];
    };

    systemd.services.test-vpn-private-key = {
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-wg0.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/private.key
        ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/private.key
      '';
    };

    systemd.services.netns-echo = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
      vpn.enable = true;
      vpn.expose.tcp = [ 8080 ];
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns-vpnapps.service")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.wait_for_unit("netns-echo.service")

    machine.succeed("ip netns list | grep -q '^vpnapps\\b'")
    machine.succeed("ip -n vpnapps link show wg0")
    machine.succeed("systemctl show -p NetworkNamespacePath --value netns-echo.service | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("test -s /run/vpn-confinement/vpnapps/resolv.conf")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'policy drop'")
  '';
}
