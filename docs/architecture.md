# Architecture

`vpn-confinement` provides fail-closed VPN confinement for selected systemd
services.

## Design

- Services opt in with `systemd.services.<name>.vpn.enable = true`.
- Confinement uses a dedicated Linux network namespace at `/run/netns/<name>`.
- WireGuard is configured natively via `networking.wireguard.interfaces.<if>`
  and assigned with `interfaceNamespace`.
- Namespace-local nftables enforces deny-by-default egress and allows only
  tunnel traffic.
- A namespace-specific `resolv.conf` is bind-mounted into confined units when
  `strictDns = true`.

## Security model

- Host network remains unchanged unless a service explicitly enables VPN
  confinement.
- Confined services fail closed if tunnel dependencies are required and
  unavailable.
- DNS leakage is reduced by restricting resolver destinations and hiding host
  resolver sockets.

## Limitations

- Application-level DoH/DoT is not fully blocked by classic DNS policy alone.
- For strict environments, combine confinement with application policy and
  egress inspection.
