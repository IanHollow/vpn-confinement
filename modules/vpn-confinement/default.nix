{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrNames
    concatMapStringsSep
    filterAttrs
    hasInfix
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optionalString
    types
    unique
    ;

  cfg = config.services.vpnConfinement;

  enabledNamespaces = filterAttrs (_: ns: ns.enable) cfg.namespaces;

  namespacePath = nsName: "/run/netns/${nsName}";
  resolvConfPath = nsName: "/run/vpn-confinement/${nsName}/resolv.conf";
  prepUnitName = nsName: "vpn-confinement-netns-${nsName}";

  renderPortSet = ports: "{ ${concatMapStringsSep ", " toString ports} }";

  dnsSplit = servers: {
    ipv4 = builtins.filter (s: !(hasInfix ":" s)) servers;
    ipv6 = builtins.filter (s: hasInfix ":" s) servers;
  };

  mkResolvText =
    dns:
    let
      nameservers = concatMapStringsSep "\n" (server: "nameserver ${server}") dns.servers;
      search =
        optionalString (dns.search != [ ])
          "search ${concatMapStringsSep " " (entry: entry) dns.search}";
    in
    ''
      ${nameservers}
      ${search}
      options edns0
    '';

  mkDnsOutputRules =
    ns:
    let
      dns = dnsSplit ns.dns.servers;
      hasV4 = dns.ipv4 != [ ];
      hasV6 = dns.ipv6 != [ ];
    in
    ''
      ${optionalString hasV4 ''
        oifname "${ns.wireguardInterface}" ip daddr ${renderPortSet dns.ipv4} udp dport 53 accept
        oifname "${ns.wireguardInterface}" ip daddr ${renderPortSet dns.ipv4} tcp dport 53 accept
      ''}
      ${optionalString hasV6 ''
        oifname "${ns.wireguardInterface}" ip6 daddr ${renderPortSet dns.ipv6} udp dport 53 accept
        oifname "${ns.wireguardInterface}" ip6 daddr ${renderPortSet dns.ipv6} tcp dport 53 accept
      ''}
      oifname "${ns.wireguardInterface}" udp dport 53 drop
      oifname "${ns.wireguardInterface}" tcp dport 53 drop
    '';

  mkNftRules =
    _: ns:
    let
      hostIngressTcp = unique ns.firewall.hostIngress.tcp;
      inboundTcp = unique ns.firewall.inbound.tcp;
      inboundUdp = unique ns.firewall.inbound.udp;
    in
    ''
      table inet vpnc {
        chain input {
          type filter hook input priority filter; policy drop;
          iifname "lo" accept
          ct state established,related accept
          ${optionalString (hostIngressTcp != [ ])
            "iifname \"${ns.veth.nsIf}\" ip saddr ${ns.veth.hostAddressIPv4} tcp dport ${renderPortSet hostIngressTcp} accept"
          }
          ${optionalString (
            inboundTcp != [ ]
          ) "iifname \"${ns.wireguardInterface}\" tcp dport ${renderPortSet inboundTcp} accept"}
          ${optionalString (
            inboundUdp != [ ]
          ) "iifname \"${ns.wireguardInterface}\" udp dport ${renderPortSet inboundUdp} accept"}
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
        }

        chain output {
          type filter hook output priority filter; policy drop;
          oifname "lo" accept
          ct state established,related accept
          ${optionalString ns.dns.blockNonConfigured (mkDnsOutputRules ns)}
          ${optionalString (ns.firewall.extraOutputAllow != [ ]) (
            concatMapStringsSep "\n" (rule: rule) ns.firewall.extraOutputAllow
          )}
          oifname "${ns.wireguardInterface}" accept
        }
      }
    '';

  namespaceUnits = mapAttrs' (
    nsName: ns:
    nameValuePair (prepUnitName nsName) {
      description = "Prepare VPN confinement namespace ${nsName}";
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-${ns.wireguardInterface}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "vpn-confinement/${nsName}";
        RuntimeDirectoryMode = "0755";
      };
      script =
        let
          nftRules = pkgs.writeText "vpn-confinement-${nsName}.nft" (mkNftRules nsName ns);
        in
        ''
          set -eu

          ${pkgs.coreutils}/bin/mkdir -p /run/netns
          if [ ! -e ${namespacePath nsName} ]; then
            ${pkgs.iproute2}/bin/ip netns add ${nsName}
          fi

          ${pkgs.iproute2}/bin/ip -n ${nsName} link set lo up

          ${pkgs.iproute2}/bin/ip link del ${ns.veth.hostIf} 2>/dev/null || true
          ${pkgs.iproute2}/bin/ip -n ${nsName} link del ${ns.veth.nsIf} 2>/dev/null || true

          ${pkgs.iproute2}/bin/ip link add ${ns.veth.hostIf} type veth peer name ${ns.veth.nsIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.veth.nsIf} netns ${nsName}
          ${pkgs.iproute2}/bin/ip addr replace ${ns.veth.hostAddressIPv4}/30 dev ${ns.veth.hostIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.veth.hostIf} up
          ${pkgs.iproute2}/bin/ip -n ${nsName} addr replace ${ns.veth.nsAddressIPv4}/30 dev ${ns.veth.nsIf}
          ${pkgs.iproute2}/bin/ip -n ${nsName} link set ${ns.veth.nsIf} up

          tmp_resolv="$(${pkgs.coreutils}/bin/mktemp ${resolvConfPath nsName}.XXXXXX)"
          ${pkgs.coreutils}/bin/cat > "$tmp_resolv" <<'EOF'
          ${mkResolvText ns.dns}
          EOF
          ${pkgs.coreutils}/bin/chmod 0444 "$tmp_resolv"
          ${pkgs.coreutils}/bin/mv -f "$tmp_resolv" ${resolvConfPath nsName}

          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft delete table inet vpnc >/dev/null 2>&1 || true
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft -f ${nftRules}
        '';
    }
  ) enabledNamespaces;

  wireguardAssignments = mapAttrs' (
    nsName: ns: nameValuePair ns.wireguardInterface { interfaceNamespace = nsName; }
  ) enabledNamespaces;
in
{
  imports = [ ./service-extension.nix ];

  options.services.vpnConfinement = {
    enable = mkEnableOption "VPN confinement for selected systemd services";

    defaultNamespace = mkOption {
      type = types.str;
      default = "vpnapps";
    };

    namespaces = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              enable = mkEnableOption "VPN confinement namespace";

              path = mkOption {
                type = types.str;
                default = namespacePath name;
                readOnly = true;
              };

              resolvConfPath = mkOption {
                type = types.str;
                default = resolvConfPath name;
                readOnly = true;
              };

              bindAddress = mkOption {
                type = types.str;
                default = config.services.vpnConfinement.namespaces.${name}.veth.nsAddressIPv4;
                readOnly = true;
              };

              wireguardInterface = mkOption {
                type = types.str;
                default = "wg0";
              };

              dns = {
                servers = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };

                search = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };

                blockNonConfigured = mkOption {
                  type = types.bool;
                  default = true;
                };
              };

              veth = {
                hostIf = mkOption {
                  type = types.str;
                  default = "ve-${name}-host";
                };

                nsIf = mkOption {
                  type = types.str;
                  default = "ve-${name}-ns";
                };

                hostAddressIPv4 = mkOption {
                  type = types.str;
                  default = "10.231.0.1";
                };

                nsAddressIPv4 = mkOption {
                  type = types.str;
                  default = "10.231.0.2";
                };
              };

              firewall = {
                hostIngress = {
                  tcp = mkOption {
                    type = types.listOf types.port;
                    default = [ ];
                  };
                };

                inbound = {
                  tcp = mkOption {
                    type = types.listOf types.port;
                    default = [ ];
                  };

                  udp = mkOption {
                    type = types.listOf types.port;
                    default = [ ];
                  };
                };

                extraOutputAllow = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };
              };
            };
          }
        )
      );
      default = {
        vpnapps.enable = true;
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.defaultNamespace cfg.namespaces;
        message = "services.vpnConfinement.defaultNamespace must exist in services.vpnConfinement.namespaces.";
      }
    ]
    ++ builtins.concatMap (
      nsName:
      let
        ns = cfg.namespaces.${nsName};
      in
      [
        {
          assertion = ns.dns.servers != [ ];
          message = "services.vpnConfinement.namespaces.${nsName}.dns.servers must be non-empty.";
        }
        {
          assertion = builtins.hasAttr ns.wireguardInterface config.networking.wireguard.interfaces;
          message = "WireGuard interface ${ns.wireguardInterface} must exist under networking.wireguard.interfaces.";
        }
      ]
    ) (attrNames enabledNamespaces);

    systemd.services = namespaceUnits;
    networking.wireguard.interfaces = wireguardAssignments;
  };
}
