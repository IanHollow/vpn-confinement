# Migration from nix-homelab inline module

## Summary

This module replaces `homelab.vpn` and per-app `*.vpn.enable` toggles with
service-local options.

## Old

- `homelab.vpn.*`
- `homelab.apps.<app>.vpn.enable`

## New

- `services.vpnConfinement.*`
- `systemd.services.<unit>.vpn.enable = true`

## Minimal migration

1. Configure `networking.wireguard.interfaces.<if>` and
   `services.vpnConfinement.namespaces.<ns>`.
2. Enable confinement for target units via `systemd.services.<name>.vpn.enable`.
3. Map web/admin exposure with `systemd.services.<name>.vpn.expose.tcp`.
4. Optionally permit inbound tunnel ports with
   `systemd.services.<name>.vpn.inbound.{tcp,udp}`.
