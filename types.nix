# NixOS option types for IP addresses, networks, endpoints, MAC addresses and netmasks.
# Exposed as `netLib.types` (and `lib.types.net` via lib-overlay.nix).
{
  lib,
  ip4,
  ip6,
  subnetRelation',
  decompose',
  decomposeEndpoint',
  checkMac,
  prefixFromNetmask',
  checkNat64Prefix,
  ...
}:
let
  inherit (lib) mkOptionType;
  inherit (lib.options) mergeEqualOption;

  mkStringType =
    {
      name,
      description,
      check,
    }:
    mkOptionType {
      inherit name description;
      descriptionClass = "noun";
      check = value: builtins.isString value && check value;
      merge = mergeEqualOption;
    };

  # Builds `<prefix>`, `<prefix>4` and `<prefix>6` style types from a check of an ipN
  # interface. `suffix` is appended to the type name, `what` to the description.
  familyTypes =
    {
      suffix,
      what,
      check,
    }:
    {
      "ip${suffix}" = mkStringType {
        name = "ip${suffix}";
        description = "IPv4 or IPv6 address${what}";
        check = value: check ip4 value || check ip6 value;
      };
      "ip4${suffix}" = mkStringType {
        name = "ip4${suffix}";
        description = "IPv4 address${what}";
        check = check ip4;
      };
      "ip6${suffix}" = mkStringType {
        name = "ip6${suffix}";
        description = "IPv6 address${what}";
        check = check ip6;
      };
    };

  # Type constructors restricting addresses to a network. `interface` is null for either
  # family (the network decides). The network is validated as soon as the type is forced.
  withinNetworkType =
    { interface, strict }:
    network:
    let
      family = if interface == null then "ip" else interface.meta.name;
      name = "${family}WithinNetwork${if strict then "Strict" else ""}";
      decomposed = decompose' network;
      validNetwork = decomposed != null && (interface == null || interface.check network);
      normalized = decomposed.network;
      relationOk = relation: relation == "equal" || (!strict && relation == "subset");
    in
    if !validNetwork then
      throw "netLib.types.${name}: invalid ${
        if interface == null then "IP" else interface.meta.description
      } network ${builtins.toJSON network}"
    else
      mkStringType {
        inherit name;
        description =
          if strict then
            "${decomposed._meta.description} in network ${normalized} with mask /${toString decomposed.mask}"
          else
            "${decomposed._meta.description} within network ${normalized} (mask optional)";
        check = value: relationOk (subnetRelation' value network);
      };

  endpointType =
    {
      name,
      description,
      family,
    }:
    mkStringType {
      inherit name description;
      check =
        value:
        let
          result = decomposeEndpoint' value;
        in
        result != null && (family == null || result.family == family);
    };
in
familyTypes {
  suffix = "";
  what = " in CIDR notation, mask optional";
  check = i: i.check;
}
// familyTypes {
  suffix = "Network";
  what = " of a normalized network in CIDR notation (no host bits set)";
  check = i: i.checkNormalizedNetwork;
}
// familyTypes {
  suffix = "NoMask";
  what = " without /mask";
  check = i: i.checkNoMask;
}
// familyTypes {
  suffix = "ExplicitMask";
  what = " with explicit /mask";
  check = i: i.checkWithMask;
}
// familyTypes {
  suffix = "Canonical";
  what = " in canonical spelling (RFC 5952 for IPv6), mask optional";
  check = i: i.checkCanonical;
}
// {
  # Addresses within a network (subset or equal, a missing mask counts as /32 or /128)
  ipWithinNetwork = withinNetworkType {
    interface = null;
    strict = false;
  };
  ip4WithinNetwork = withinNetworkType {
    interface = ip4;
    strict = false;
  };
  ip6WithinNetwork = withinNetworkType {
    interface = ip6;
    strict = false;
  };

  # Addresses within a network with the same mask as the network
  ipWithinNetworkStrict = withinNetworkType {
    interface = null;
    strict = true;
  };
  ip4WithinNetworkStrict = withinNetworkType {
    interface = ip4;
    strict = true;
  };
  ip6WithinNetworkStrict = withinNetworkType {
    interface = ip6;
    strict = true;
  };

  port = lib.types.port;

  # Privileged ports need root or CAP_NET_BIND_SERVICE to bind on Linux
  privilegedPort = lib.types.ints.between 0 1023;
  unprivilegedPort = lib.types.ints.between 1024 65535;

  # IANA port ranges (RFC 6335)
  wellKnownPort = lib.types.ints.between 0 1023;
  registeredPort = lib.types.ints.between 1024 49151;
  dynamicPort = lib.types.ints.between 49152 65535;

  endpoint = endpointType {
    name = "endpoint";
    description = "IPv4 or IPv6 endpoint (\"1.2.3.4:53\" or \"[2001:db8::1]:53\")";
    family = null;
  };
  ip4Endpoint = endpointType {
    name = "ip4Endpoint";
    description = "IPv4 endpoint (\"1.2.3.4:53\")";
    family = "ip4";
  };
  ip6Endpoint = endpointType {
    name = "ip6Endpoint";
    description = "IPv6 endpoint (\"[2001:db8::1]:53\")";
    family = "ip6";
  };

  mac = mkStringType {
    name = "mac";
    description = "MAC address (six hex byte pairs separated by \":\" or \"-\")";
    check = checkMac;
  };

  nat64Prefix = mkStringType {
    name = "nat64Prefix";
    description = "NAT64 prefix (IPv6 network of length 32, 40, 48, 56, 64 or 96 with bits 64 to 71 zero, RFC 6052)";
    check = checkNat64Prefix;
  };

  ip4Netmask = mkStringType {
    name = "ip4Netmask";
    description = "contiguous IPv4 netmask (e.g. \"255.255.255.0\")";
    check = value: ip4.checkNoMask value && prefixFromNetmask' value != null;
  };

  ip4PrefixLength = lib.types.ints.between 0 32;
  ip6PrefixLength = lib.types.ints.between 0 128;
}
