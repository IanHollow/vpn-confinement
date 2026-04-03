_: {
  perSystem =
    { pkgs, ... }:
    {
      checks.vpn-confinement-basic = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-basic.nix { inherit pkgs; }
      );

      checks.vpn-confinement-leak-tests = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-leak-tests.nix { inherit pkgs; }
      );
    };
}
