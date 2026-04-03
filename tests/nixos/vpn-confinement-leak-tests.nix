{ pkgs, ... }:
{
  name = "vpn-confinement-leak-tests";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-leaks";
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
      ips = [ "10.71.216.231/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          persistentKeepalive = 25;
          allowedIPs = [ "0.0.0.0/0" ];
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

    systemd.services.netns-probe = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
      vpn.enable = true;
      vpn.strictDns = true;
    };

    environment.systemPackages = [
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("netns-probe.service")

    machine.succeed("systemctl show -p NetworkNamespacePath --value netns-probe.service | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'udp dport 53 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'tcp dport 53 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'oifname \"wg0\" accept'")
  '';
}
