# Test cases for netLib.types (option types). See ../tests.nix for the format:
# a function `{ lib, netLib, throws, ... }` returning a list of
# `{ description = "..."; expression = <value>; expected = <value>; }`.
{
  lib,
  netLib,
  throws,
  ...
}:
with builtins;
with lib;
with netLib;
let
  t = netLib.types;

  # Generates one test case per value: `types.<name>.check value == expected`
  checks =
    name: expected: values:
    map (value: {
      description = "types.${name}.check ${toJSON value} is ${boolToString expected}";
      expression = t.${name}.check value;
      inherit expected;
    }) values;

  checksOf =
    label: type: expected: values:
    map (value: {
      description = "${label}.check ${toJSON value} is ${boolToString expected}";
      expression = type.check value;
      inherit expected;
    }) values;

  evalModule =
    config:
    (lib.evalModules {
      modules = [
        {
          options = {
            address = mkOption { type = t.ip6NoMask; };
            addresses = mkOption {
              type = lib.types.listOf t.ip;
              default = [ ];
            };
            lanHost = mkOption { type = t.ip4WithinNetwork "192.168.1.0/24"; };
            dns = mkOption { type = t.endpoint; };
            mac = mkOption { type = t.mac; };
            prefix = mkOption { type = t.ip4PrefixLength; };
          };
        }
      ]
      ++ config;
    }).config;

  validConfig = [
    {
      address = "2001:db8::1";
      addresses = [ "10.0.0.1/8" ];
      lanHost = "192.168.1.10";
      dns = "[2001:db8::53]:53";
      mac = "00:11:22:33:44:55";
      prefix = 24;
    }
    {
      address = "2001:db8::1";
      addresses = [ "fe80::1/64" ];
    }
  ];
in
# Plain addresses, mask optional
checks "ip" true [
  "1.2.3.4"
  "1.2.3.4/24"
  "::1"
  "2001:DB8::1/64"
]
++ checks "ip" false [
  "1.2.3.4/33"
  "foo"
  ""
  5
  null
  "1.2.3"
  "::1/129"
]
++ checks "ip4" true [
  "1.2.3.4"
  "0.0.0.0/0"
]
++ checks "ip4" false [
  "::1"
  "01.2.3.4"
  "256.1.1.1"
]
++ checks "ip6" true [
  "::1"
  "::ffff:1.2.3.4/96"
]
++ checks "ip6" false [
  "1.2.3.4"
  "1::2::3"
]

# Normalized networks
++ checks "ipNetwork" true [
  "10.0.0.0/8"
  "2001:db8::/32"
  "1.2.3.4"
]
++ checks "ipNetwork" false [
  "10.0.0.1/8"
  "2001:db8::1/32"
  "foo"
]
++ checks "ip4Network" true [ "192.168.0.0/16" ]
++ checks "ip4Network" false [
  "192.168.0.1/16"
  "2001:db8::/32"
]
++ checks "ip6Network" true [ "fe80::/10" ]
++ checks "ip6Network" false [
  "fe80::1/10"
  "10.0.0.0/8"
]

# Without mask
++ checks "ipNoMask" true [
  "1.2.3.4"
  "2001:DB8:0::1"
]
++ checks "ipNoMask" false [
  "1.2.3.4/32"
  "::1/128"
  "foo"
]
++ checks "ip4NoMask" true [ "1.2.3.4" ]
++ checks "ip4NoMask" false [
  "1.2.3.4/32"
  "::1"
]
++ checks "ip6NoMask" true [ "::1" ]
++ checks "ip6NoMask" false [
  "::1/128"
  "1.2.3.4"
]

# Explicit mask
++ checks "ipExplicitMask" true [
  "1.2.3.4/32"
  "::1/128"
]
++ checks "ipExplicitMask" false [
  "1.2.3.4"
  "::1"
  "1.2.3.4/"
]
++ checks "ip4ExplicitMask" true [ "10.0.0.1/8" ]
++ checks "ip4ExplicitMask" false [
  "10.0.0.1"
  "::1/64"
]
++ checks "ip6ExplicitMask" true [ "fe80::1/64" ]
++ checks "ip6ExplicitMask" false [
  "fe80::1"
  "10.0.0.1/8"
]

# Canonical spelling
++ checks "ipCanonical" true [
  "1.2.3.4"
  "2001:db8::1/64"
  "::ffff:1.2.3.4"
]
++ checks "ipCanonical" false [
  "2001:DB8::1"
  "2001:db8:0::1"
  "::ffff:102:304"
  "foo"
]
++ checks "ip4Canonical" true [ "1.2.3.4/24" ]
++ checks "ip4Canonical" false [ "::1" ]
++ checks "ip6Canonical" true [
  "fe80::1"
  "2001:db8:0:1:1:1:1:1"
]
++ checks "ip6Canonical" false [
  "fe80:0::1"
  "2001:db8::1:1:1:1:1"
  "1.2.3.4"
]

# Within network
++ checksOf "ip4WithinNetwork \"10.0.0.0/8\"" (t.ip4WithinNetwork "10.0.0.0/8") true [
  "10.1.2.3"
  "10.1.0.0/16"
  "10.0.0.0/8"
]
++ checksOf "ip4WithinNetwork \"10.0.0.0/8\"" (t.ip4WithinNetwork "10.0.0.0/8") false [
  "11.0.0.1"
  "10.0.0.0/7"
  "::1"
  "foo"
  3
]
++ checksOf "ip4WithinNetworkStrict \"10.0.0.0/8\"" (t.ip4WithinNetworkStrict "10.0.0.0/8") true [
  "10.1.2.3/8"
  "10.0.0.0/8"
]
++ checksOf "ip4WithinNetworkStrict \"10.0.0.0/8\"" (t.ip4WithinNetworkStrict "10.0.0.0/8") false [
  "10.1.2.3"
  "10.1.0.0/16"
  "11.0.0.1/8"
]
++ checksOf "ip6WithinNetwork \"2001:db8::/32\"" (t.ip6WithinNetwork "2001:db8::/32") true [
  "2001:db8::1"
  "2001:DB8:1::/48"
]
++ checksOf "ip6WithinNetwork \"2001:db8::/32\"" (t.ip6WithinNetwork "2001:db8::/32") false [
  "2001:db9::1"
  "10.0.0.1"
]
++
  checksOf "ip6WithinNetworkStrict \"2001:db8::/32\"" (t.ip6WithinNetworkStrict "2001:db8::/32") true
    [ "2001:db8::1/32" ]
++
  checksOf "ip6WithinNetworkStrict \"2001:db8::/32\"" (t.ip6WithinNetworkStrict "2001:db8::/32") false
    [
      "2001:db8::1"
      "2001:db8::/48"
    ]
++ checksOf "ipWithinNetwork \"fe80::/10\"" (t.ipWithinNetwork "fe80::/10") true [ "fe80::1" ]
++ checksOf "ipWithinNetwork \"fe80::/10\"" (t.ipWithinNetwork "fe80::/10") false [
  "10.0.0.1"
  "fec0::1"
]
++ checksOf "ipWithinNetwork \"10.0.0.0/8\"" (t.ipWithinNetwork "10.0.0.0/8") true [ "10.0.0.1" ]
++ checksOf "ipWithinNetworkStrict \"10.0.0.0/8\"" (t.ipWithinNetworkStrict "10.0.0.0/8") true [
  "10.0.0.1/8"
]
++ checksOf "ipWithinNetworkStrict \"10.0.0.0/8\"" (t.ipWithinNetworkStrict "10.0.0.0/8") false [
  "10.0.0.1"
]

# Endpoints
++ checks "endpoint" true [
  "1.2.3.4:53"
  "[2001:db8::1]:53"
  "[::ffff:1.2.3.4]:0"
  "1.2.3.4:65535"
]
++ checks "endpoint" false [
  "1.2.3.4"
  "1.2.3.4:65536"
  "1.2.3.4:053"
  "1.2.3.4/24:53"
  "[2001:db8::1/64]:53"
  "2001:db8::1:53"
  "[1.2.3.4]:53"
  "[::1]"
  ":53"
  null
]
++ checks "ip4Endpoint" true [ "127.0.0.1:8080" ]
++ checks "ip4Endpoint" false [
  "[::1]:8080"
  "256.0.0.1:80"
]
++ checks "ip6Endpoint" true [
  "[::1]:8080"
  "[2001:DB8::1]:443"
]
++ checks "ip6Endpoint" false [
  "127.0.0.1:8080"
  "::1:8080"
]
++ checks "port" true [
  0
  53
  65535
]
++ checks "port" false [
  (-1)
  65536
  "53"
]
++ checks "privilegedPort" true [
  0
  22
  1023
]
++ checks "privilegedPort" false [
  (-1)
  1024
  "22"
]
++ checks "unprivilegedPort" true [
  1024
  8080
  65535
]
++ checks "unprivilegedPort" false [
  1023
  65536
  "8080"
]
++ checks "wellKnownPort" true [
  0
  443
  1023
]
++ checks "wellKnownPort" false [ 1024 ]
++ checks "registeredPort" true [
  1024
  8080
  49151
]
++ checks "registeredPort" false [
  1023
  49152
]
++ checks "dynamicPort" true [
  49152
  60000
  65535
]
++ checks "dynamicPort" false [
  49151
  65536
]

# MAC addresses
++ checks "mac" true [
  "00:11:22:33:44:55"
  "AA-bb-CC-dd-EE-ff"
]
++ checks "mac" false [
  "00:11:22:33:44"
  "00:11:22-33:44:55"
  "001122334455"
  "00:11:22:33:44:5g"
  "0:11:22:33:44:55"
  1
]

# Netmasks and prefix lengths
++ checks "ip4Netmask" true [
  "255.255.255.0"
  "0.0.0.0"
  "255.255.255.255"
  "255.128.0.0"
]
++ checks "ip4Netmask" false [
  "255.0.255.0"
  "255.255.255.0/24"
  "ffff::"
  "255.255.255.1"
]
++ checks "nat64Prefix" true [
  "64:ff9b::/96"
  "64:ff9b:1::/48"
  "2001:db8:100::/40"
]
++ checks "nat64Prefix" false [
  "2001:db8::/80"
  "64:ff9b::"
  "2001:db8::1/96"
  96
]
++ checks "ip4PrefixLength" true [
  0
  32
]
++ checks "ip4PrefixLength" false [
  (-1)
  33
  "24"
]
++ checks "ip6PrefixLength" true [
  0
  64
  128
]
++ checks "ip6PrefixLength" false [ 129 ]
++ [
  # Type metadata
  {
    description = "combined types are single option types with static names";
    expression = map (name: t.${name}.name) [
      "ip"
      "ipNetwork"
      "ipNoMask"
      "ipExplicitMask"
      "ipCanonical"
    ];
    expected = [
      "ip"
      "ipNetwork"
      "ipNoMask"
      "ipExplicitMask"
      "ipCanonical"
    ];
  }
  {
    description = "combined type description names both families";
    expression = t.ip.description;
    expected = "IPv4 or IPv6 address in CIDR notation, mask optional";
  }
  {
    description = "within network type has a static name and the normalized network in its description";
    expression = with t.ip4WithinNetwork "10.1.2.3/8"; {
      inherit name;
      hasNetwork = hasInfix "10.0.0.0/8" description;
    };
    expected = {
      name = "ip4WithinNetwork";
      hasNetwork = true;
    };
  }
  {
    description = "strict within network type name";
    expression = (t.ip6WithinNetworkStrict "2001:DB8::/32").name;
    expected = "ip6WithinNetworkStrict";
  }

  # Eager network validation
  {
    description = "ip4WithinNetwork throws for an invalid network";
    expression = throws (t.ip4WithinNetwork "10.0.0.0/33");
    expected = true;
  }
  {
    description = "ip4WithinNetwork throws for an IPv6 network";
    expression = throws (t.ip4WithinNetwork "2001:db8::/32");
    expected = true;
  }
  {
    description = "ip6WithinNetworkStrict throws for an IPv4 network";
    expression = throws (t.ip6WithinNetworkStrict "10.0.0.0/8");
    expected = true;
  }
  {
    description = "ipWithinNetwork throws for garbage";
    expression = throws (t.ipWithinNetwork "foo");
    expected = true;
  }
  {
    description = "ipWithinNetworkStrict throws for a non-string";
    expression = throws (t.ipWithinNetworkStrict 42);
    expected = true;
  }
  {
    description = "ip4WithinNetwork does not throw for a valid network";
    expression = throws (t.ip4WithinNetwork "10.0.0.0/8");
    expected = false;
  }

  # Endpoint functions
  {
    description = "decomposeEndpoint IPv4";
    expression = decomposeEndpoint "1.2.3.4:53";
    expected = {
      address = "1.2.3.4";
      port = 53;
      family = "ip4";
    };
  }
  {
    description = "decomposeEndpoint IPv6 canonicalizes the address";
    expression = decomposeEndpoint "[2001:DB8:0::1]:443";
    expected = {
      address = "2001:db8::1";
      port = 443;
      family = "ip6";
    };
  }
  {
    description = "decomposeEndpoint port 0 and 65535";
    expression = map (e: (decomposeEndpoint e).port) [
      "[::]:0"
      "0.0.0.0:65535"
    ];
    expected = [
      0
      65535
    ];
  }
  {
    description = "decomposeEndpoint' returns null for invalid input";
    expression = map decomposeEndpoint' [
      "1.2.3.4"
      "1.2.3.4:65536"
      "1.2.3.4:01"
      "[::1/128]:53"
      "::1:53"
      5
    ];
    expected = [
      null
      null
      null
      null
      null
      null
    ];
  }
  {
    description = "decomposeEndpoint throws for invalid input";
    expression = throws (decomposeEndpoint "1.2.3.4:99999");
    expected = true;
  }

  # MAC functions
  {
    description = "checkMac";
    expression = map checkMac [
      "00:1a:2B:3c:4d:5e"
      "00-1a-2B-3c-4d-5e"
      "00:1a-2B:3c:4d:5e"
      "00:1a:2B:3c:4d"
    ];
    expected = [
      true
      true
      false
      false
    ];
  }
  {
    description = "macToParts with colons";
    expression = macToParts "00:1A:2b:3c:4d:FF";
    expected = [
      0
      26
      43
      60
      77
      255
    ];
  }
  {
    description = "macToParts with dashes";
    expression = macToParts "02-00-00-00-00-01";
    expected = [
      2
      0
      0
      0
      0
      1
    ];
  }
  {
    description = "macToParts' returns null for invalid input";
    expression = map macToParts' [
      "00:11:22:33:44"
      "zz:11:22:33:44:55"
      null
    ];
    expected = [
      null
      null
      null
    ];
  }
  {
    description = "macToParts throws for invalid input";
    expression = throws (macToParts "00:11:22:33:44");
    expected = true;
  }

  # Netmask functions
  {
    description = "prefixFromNetmask IPv4";
    expression = map prefixFromNetmask [
      "255.255.255.0"
      "0.0.0.0"
      "255.255.255.255"
      "255.255.240.0"
    ];
    expected = [
      24
      0
      32
      20
    ];
  }
  {
    description = "prefixFromNetmask IPv6";
    expression = map prefixFromNetmask [
      "ffff:ffff:ffff:ffff::"
      "::"
      "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
      "fe00::"
    ];
    expected = [
      64
      0
      128
      7
    ];
  }
  {
    description = "prefixFromNetmask' returns null for non-contiguous, masked or invalid input";
    expression = map prefixFromNetmask' [
      "255.0.255.0"
      "255.255.255.0/24"
      "0.0.0.1"
      "ffff::ffff"
      "foo"
      24
    ];
    expected = [
      null
      null
      null
      null
      null
      null
    ];
  }
  {
    description = "prefixFromNetmask throws for non-contiguous netmask";
    expression = throws (prefixFromNetmask "255.255.0.255");
    expected = true;
  }
  {
    description = "ip4.netmaskFromPrefix";
    expression = map ip4.netmaskFromPrefix [
      0
      8
      24
      25
      32
    ];
    expected = [
      "0.0.0.0"
      "255.0.0.0"
      "255.255.255.0"
      "255.255.255.128"
      "255.255.255.255"
    ];
  }
  {
    description = "ip6.netmaskFromPrefix";
    expression = map ip6.netmaskFromPrefix [
      0
      32
      64
      127
    ];
    expected = [
      "::"
      "ffff:ffff::"
      "ffff:ffff:ffff:ffff::"
      "ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe"
    ];
  }
  {
    description = "netmaskFromPrefix and prefixFromNetmask round trip";
    expression = all (p: prefixFromNetmask (ip4.netmaskFromPrefix p) == p) (genList (i: i) 33);
    expected = true;
  }
  {
    description = "netmaskFromPrefix throws for out of range prefix";
    expression = map (x: throws x) [
      (ip4.netmaskFromPrefix 33)
      (ip6.netmaskFromPrefix (-1))
    ];
    expected = [
      true
      true
    ];
  }

  # Module system integration
  {
    description = "evalModules merges values of netLib types";
    expression = evalModule validConfig;
    expected = {
      address = "2001:db8::1";
      addresses = [
        "fe80::1/64"
        "10.0.0.1/8"
      ]; # later modules are merged first
      lanHost = "192.168.1.10";
      dns = "[2001:db8::53]:53";
      mac = "00:11:22:33:44:55";
      prefix = 24;
    };
  }
  {
    description = "evalModules rejects conflicting definitions of a unique type";
    expression = throws (evalModule (validConfig ++ [ { address = "2001:db8::2"; } ])).address;
    expected = true;
  }
  {
    description = "evalModules rejects a value outside the network";
    expression = throws (evalModule (validConfig ++ [ { lanHost = mkForce "192.168.2.10"; } ])).lanHost;
    expected = true;
  }
  {
    description = "evalModules rejects an invalid endpoint";
    expression = throws (evalModule [ (head validConfig // { dns = "2001:db8::53:53"; }) ]).dns;
    expected = true;
  }
]
