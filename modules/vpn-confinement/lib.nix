{ lib }:
let
  inherit (lib)
    concatMapStringsSep
    hasInfix
    optionalString
    unique
    ;
in
{
  uniquePorts = unique;

  renderPortSet = ports: "{ ${concatMapStringsSep ", " toString ports} }";

  splitDns = servers: {
    ipv4 = builtins.filter (s: !(hasInfix ":" s)) servers;
    ipv6 = builtins.filter (s: hasInfix ":" s) servers;
  };

  renderResolvConf =
    dns:
    let
      nameservers = concatMapStringsSep "\n" (server: "nameserver ${server}") dns.servers;
      search = optionalString (dns.search != [ ]) "search ${concatMapStringsSep " " dns.search}";
    in
    ''
      ${nameservers}
      ${search}
      options edns0
    '';
}
