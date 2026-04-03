_: {
  flake.nixosModules = {
    default = ../../modules/vpn-confinement/default.nix;
    vpn-confinement = ../../modules/vpn-confinement/default.nix;
  };
}
