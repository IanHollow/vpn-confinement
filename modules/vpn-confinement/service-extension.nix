{ lib, config, ... }:
let
  inherit (lib)
    attrNames
    filterAttrs
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionals
    optionalAttrs
    types
    ;

  cfg = config.services.vpnConfinement;

  vpnEnabledServiceNames = attrNames (filterAttrs (_: defaults: defaults.enable) cfg.serviceDefaults);

  defaultsFor = serviceName: cfg.serviceDefaults.${serviceName};

  nsFor =
    serviceName:
    let
      defaults = defaultsFor serviceName;
    in
    if defaults.namespace != null then defaults.namespace else cfg.defaultNamespace;

  serviceAssertions = builtins.concatMap (
    serviceName:
    let
      defaults = defaultsFor serviceName;
      nsName = nsFor serviceName;
    in
    [
      {
        assertion = builtins.hasAttr serviceName cfg.serviceDefaults;
        message = "Missing services.vpnConfinement.serviceDefaults.${serviceName} for vpn-enabled service.";
      }
      {
        assertion = builtins.hasAttr nsName cfg.namespaces;
        message = "services.vpnConfinement.serviceDefaults.${serviceName} references unknown namespace ${nsName}.";
      }
      {
        assertion = cfg.namespaces.${nsName}.enable;
        message = "services.vpnConfinement.serviceDefaults.${serviceName} references disabled namespace ${nsName}.";
      }
      {
        assertion = defaults.enable;
        message = "services.vpnConfinement.serviceDefaults.${serviceName}.enable must be true for vpn-enabled service.";
      }
    ]
  ) vpnEnabledServiceNames;

  hardeningBaseline = {
    NoNewPrivileges = lib.mkDefault true;
    PrivateTmp = lib.mkDefault true;
    PrivateDevices = lib.mkDefault true;
    ProtectSystem = lib.mkDefault "strict";
    ProtectHome = lib.mkDefault true;
    ProtectControlGroups = lib.mkDefault true;
    ProtectKernelModules = lib.mkDefault true;
    ProtectKernelTunables = lib.mkDefault true;
    ProtectKernelLogs = lib.mkDefault true;
    RestrictSUIDSGID = lib.mkDefault true;
    RestrictNamespaces = lib.mkDefault true;
    LockPersonality = lib.mkDefault true;
    CapabilityBoundingSet = lib.mkDefault "";
    AmbientCapabilities = lib.mkDefault [ ];
    ProtectProc = lib.mkDefault "invisible";
    ProcSubset = lib.mkDefault "pid";
    UMask = lib.mkDefault "0007";
  };

  hardeningStrict = {
    ProtectClock = lib.mkDefault true;
    ProtectHostname = lib.mkDefault true;
    RestrictRealtime = lib.mkDefault true;
    MemoryDenyWriteExecute = lib.mkDefault true;
    SystemCallArchitectures = lib.mkDefault "native";
    SystemCallFilter = lib.mkDefault [ "@system-service" ];
    SystemCallErrorNumber = lib.mkDefault "EPERM";
  };
in
{
  options.systemd.services = mkOption {
    type = types.attrsOf (
      types.submodule {
        options.vpn.enable = mkEnableOption "run this unit in the VPN confinement namespace";
      }
    );
  };

  options.services.vpnConfinement.serviceDefaults = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          enable = mkEnableOption "VPN confinement defaults for this unit";

          namespace = mkOption {
            type = types.nullOr types.str;
            default = null;
          };

          strictDns = mkOption {
            type = types.bool;
            default = true;
          };

          dependsOnTunnel = mkOption {
            type = types.bool;
            default = true;
          };

          hardeningProfile = mkOption {
            type = types.enum [
              "baseline"
              "strict"
            ];
            default = "baseline";
          };

          expose.tcp = mkOption {
            type = types.listOf types.port;
            default = [ ];
          };

          inbound.tcp = mkOption {
            type = types.listOf types.port;
            default = [ ];
          };

          inbound.udp = mkOption {
            type = types.listOf types.port;
            default = [ ];
          };
        };
      }
    );
    default = { };
  };

  config = mkIf cfg.enable {
    assertions = serviceAssertions;

    systemd.services = mkMerge (
      builtins.map (
        serviceName:
        let
          defaults = defaultsFor serviceName;
          nsName = nsFor serviceName;
          ns = cfg.namespaces.${nsName};
          hardening =
            hardeningBaseline // optionalAttrs (defaults.hardeningProfile == "strict") hardeningStrict;
        in
        {
          ${serviceName} = {
            after = optionals defaults.dependsOnTunnel [
              "vpn-confinement-netns-${nsName}.service"
              "wireguard-${ns.wireguardInterface}.service"
            ];
            requires = optionals defaults.dependsOnTunnel [
              "vpn-confinement-netns-${nsName}.service"
              "wireguard-${ns.wireguardInterface}.service"
            ];
            serviceConfig = hardening // {
              NetworkNamespacePath = "/run/netns/${nsName}";
              BindReadOnlyPaths = optionals defaults.strictDns [ "${ns.resolvConfPath}:/etc/resolv.conf" ];
              InaccessiblePaths = optionals defaults.strictDns [
                "/run/nscd"
                "/run/resolvconf"
                "-/run/systemd/resolve"
              ];
            };
          };
        }
      ) vpnEnabledServiceNames
    );

    services.vpnConfinement.namespaces = mkMerge (
      builtins.map (
        serviceName:
        let
          defaults = defaultsFor serviceName;
          nsName = nsFor serviceName;
        in
        {
          ${nsName} = {
            firewall.hostIngress.tcp = defaults.expose.tcp;
            firewall.inbound.tcp = defaults.inbound.tcp;
            firewall.inbound.udp = defaults.inbound.udp;
          };
        }
      ) vpnEnabledServiceNames
    );
  };
}
