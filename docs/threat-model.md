# Threat model

## In scope

- Prevent non-confined host traffic from being forced through the VPN.
- Prevent confined services from egressing outside the tunnel when kill-switch
  is active.
- Reduce classic DNS leaks from confined services.

## Out of scope

- Full prevention of application-level encrypted DNS (DoH/DoT) without deeper
  traffic controls.
- Protection against compromised root on the host.

## Controls

- Network namespace isolation per confinement domain.
- Namespace-local nftables output default drop.
- WireGuard-only egress allowlist.
- Resolver bind mount and inaccessible host resolver helper paths.
