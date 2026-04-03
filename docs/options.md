# Options

## Global

- `services.vpnConfinement.enable`
- `services.vpnConfinement.defaultNamespace`
- `services.vpnConfinement.namespaces.<name>.enable`
- `services.vpnConfinement.namespaces.<name>.wireguardInterface`
- `services.vpnConfinement.namespaces.<name>.dns.servers`
- `services.vpnConfinement.namespaces.<name>.dns.search`
- `services.vpnConfinement.namespaces.<name>.firewall.*`

## Per service

- `systemd.services.<name>.vpn.enable`
- `systemd.services.<name>.vpn.namespace`
- `systemd.services.<name>.vpn.strictDns`
- `systemd.services.<name>.vpn.dependsOnTunnel`
- `systemd.services.<name>.vpn.hardeningProfile`
- `systemd.services.<name>.vpn.expose.tcp`
- `systemd.services.<name>.vpn.inbound.tcp`
- `systemd.services.<name>.vpn.inbound.udp`
