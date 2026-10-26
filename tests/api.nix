# Test cases for the public API of netLib. See ../tests.nix for the format:
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
  case = description: expression: expected: { inherit description expression expected; };
  fails = description: expression: case description (throws expression) true;

  hashedNames =
    names:
    map (
      name:
      hashedAddress {
        salt = "s";
        network = "2001:db8::/64";
        inherit name;
      }
    ) names;
in
[
  # inSubnet / inSubnet' and the deprecated laysWithinSubnet aliases
  (case "inSubnet: address inside /8" (inSubnet "10.1.2.3" "10.0.0.0/8") true)
  (case "inSubnet: address outside /8" (inSubnet "11.0.0.1" "10.0.0.0/8") false)
  (case "inSubnet: equal network" (inSubnet "10.0.0.0/8" "10.0.0.0/8") true)
  (case "inSubnet: superset is not inside" (inSubnet "10.0.0.0/8" "10.0.0.0/16") false)
  (case "inSubnet: IPv6 address with longer mask" (inSubnet "fd00::1/64" "fd00::/8") true)
  (fails "inSubnet: mixed families throw" (inSubnet "10.0.0.1" "::/0"))
  (fails "inSubnet: invalid input throws" (inSubnet "foo" "10.0.0.0/8"))
  (case "inSubnet': mixed families are false" (inSubnet' "10.0.0.1" "::/0") false)
  (case "inSubnet': invalid input is false" (inSubnet' "foo" "10.0.0.0/8") false)
  (case "inSubnet': address inside" (inSubnet' "2001:db8::1" "2001:db8::/32") true)
  (case "laysWithinSubnet alias" (laysWithinSubnet "fd00::1/64" "fd00::/8") true)
  (case "laysWithinSubnet' alias" (laysWithinSubnet' "11.0.0.1" "10.0.0.0/8") false)
  (fails "laysWithinSubnet alias throws on invalid input" (laysWithinSubnet "x" "y"))

  # broadcast
  (case "broadcast of a /24" (broadcast "10.0.0.0/24") "10.0.0.255")
  (case "broadcast of a /23 crosses an octet" (broadcast "10.0.0.0/23") "10.0.1.255")
  (case "broadcast ignores device bits" (broadcast "10.0.0.77/23") "10.0.1.255")
  (case "broadcast of a /31" (broadcast "192.168.1.0/31") "192.168.1.1")
  (case "broadcast of an address without mask" (broadcast "192.168.1.5") "192.168.1.5")
  (case "broadcast of /0" (broadcast "0.0.0.0/0") "255.255.255.255")
  (fails "broadcast throws for IPv6" (broadcast "fe80::/64"))
  (fails "broadcast throws for invalid input" (broadcast "foo"))

  # firstHost / lastHost / hostCount, IPv4
  (case "firstHost of a /24" (firstHost "10.0.0.0/24") "10.0.0.1")
  (case "lastHost of a /24" (lastHost "10.0.0.0/24") "10.0.0.254")
  (case "hostCount of a /24" (hostCount "10.0.0.0/24") 254)
  (case "firstHost ignores device bits" (firstHost "10.0.0.77/24") "10.0.0.1")
  (case "lastHost of a /23 is in the second octet" (lastHost "10.0.0.0/23") "10.0.1.254")
  (case "firstHost of a /23" (firstHost "10.0.0.0/23") "10.0.0.1")
  (case "hostCount of a /23" (hostCount "10.0.0.0/23") 510)
  (case "hostCount of a /16" (hostCount "172.16.0.0/16") 65534)
  (case "firstHost of a /30" (firstHost "10.0.0.4/30") "10.0.0.5")
  (case "lastHost of a /30" (lastHost "10.0.0.4/30") "10.0.0.6")
  (case "hostCount of a /30" (hostCount "10.0.0.4/30") 2)
  (case "firstHost of a /31 (RFC 3021)" (firstHost "192.168.1.0/31") "192.168.1.0")
  (case "lastHost of a /31 (RFC 3021)" (lastHost "192.168.1.0/31") "192.168.1.1")
  (case "hostCount of a /31" (hostCount "192.168.1.0/31") 2)
  (case "firstHost of a /32" (firstHost "192.168.1.5/32") "192.168.1.5")
  (case "lastHost of a /32" (lastHost "192.168.1.5/32") "192.168.1.5")
  (case "hostCount of a /32" (hostCount "192.168.1.5/32") 1)
  (case "firstHost without mask is the address" (firstHost "192.168.1.5") "192.168.1.5")
  (case "hostCount without mask" (hostCount "192.168.1.5") 1)
  (case "firstHost of /0" (firstHost "0.0.0.0/0") "0.0.0.1")
  (case "lastHost of /0" (lastHost "0.0.0.0/0") "255.255.255.254")
  (case "hostCount of IPv4 /0" (hostCount "0.0.0.0/0") 4294967294)
  (case "lastHost of 10.0.0.0/8" (lastHost "10.0.0.0/8") "10.255.255.254")

  # firstHost / lastHost / hostCount, IPv6
  (case "firstHost of an IPv6 /64 skips the subnet-router anycast" (firstHost "2001:db8::/64")
    "2001:db8::1"
  )
  (case "lastHost of an IPv6 /64" (lastHost "2001:db8::/64") "2001:db8::ffff:ffff:ffff:ffff")
  (case "lastHost of an IPv6 /48" (lastHost "2001:db8:1::/48") "2001:db8:1:ffff:ffff:ffff:ffff:ffff")
  (case "firstHost ignores IPv6 device bits" (firstHost "2001:DB8::abcd/64") "2001:db8::1")
  (case "firstHost of an IPv6 /120" (firstHost "2001:db8::/120") "2001:db8::1")
  (case "lastHost of an IPv6 /120" (lastHost "2001:db8::/120") "2001:db8::ff")
  (case "hostCount of an IPv6 /120" (hostCount "2001:db8::/120") 255)
  (case "firstHost of an IPv6 /127 (RFC 6164)" (firstHost "2001:db8::/127") "2001:db8::")
  (case "lastHost of an IPv6 /127 (RFC 6164)" (lastHost "2001:db8::/127") "2001:db8::1")
  (case "hostCount of an IPv6 /127" (hostCount "2001:db8::/127") 2)
  (case "firstHost of an IPv6 /128" (firstHost "2001:db8::5/128") "2001:db8::5")
  (case "lastHost of an IPv6 /128" (lastHost "2001:db8::5/128") "2001:db8::5")
  (case "hostCount of an IPv6 address without mask" (hostCount "::1") 1)
  (case "lastHost of an IPv6 address without mask" (lastHost "::1") "::1")
  (case "firstHost of ::/0" (firstHost "::/0") "::1")
  (case "lastHost of ::/0" (lastHost "::/0") "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
  (case "hostCount of an IPv6 /66 is 2^62 - 1" (hostCount "2001:db8::/66") 4611686018427387903)
  (case "hostCount of an IPv6 /65 is 2^63 - 1 (largest Nix int)" (hostCount "2001:db8::/65")
    9223372036854775807
  )
  (case "lastHost of an IPv6 /65" (lastHost "2001:db8::/65") "2001:db8::7fff:ffff:ffff:ffff")
  (fails "hostCount of an IPv6 /64 does not fit into an int" (hostCount "2001:db8::/64"))
  (fails "hostCount of ::/0 does not fit into an int" (hostCount "::/0"))
  (case "firstHost of an IPv4-mapped /120" (firstHost "::ffff:10.0.0.0/120") "::ffff:10.0.0.1")
  (case "lastHost of an IPv4-mapped /120 (IPv6 rules)" (lastHost "::ffff:10.0.0.0/120")
    "::ffff:10.0.0.255"
  )
  (case "hostCount of an IPv4-mapped /120 (IPv6 rules)" (hostCount "::ffff:10.0.0.0/120") 255)
  (fails "firstHost throws for invalid input" (firstHost "foo"))
  (fails "lastHost throws for an invalid mask" (lastHost "1.2.3.4/33"))
  (fails "hostCount throws for invalid input" (hostCount "::g"))

  # overlaps
  (case "overlaps: superset" (overlaps "10.0.0.0/8" "10.1.0.0/16") true)
  (case "overlaps: subset" (overlaps "10.1.0.0/16" "10.0.0.0/8") true)
  (case "overlaps: equal" (overlaps "10.0.0.0/24" "10.0.0.0/24") true)
  (case "overlaps: adjacent networks" (overlaps "10.0.0.0/24" "10.0.1.0/24") false)
  (case "overlaps: address inside network" (overlaps "10.0.0.5" "10.0.0.0/24") true)
  (case "overlaps: disjoint IPv6" (overlaps "fd00::/8" "fe80::/10") false)
  (case "overlaps: IPv6 subset" (overlaps "fd00::/8" "fd12:3456::/32") true)
  (fails "overlaps: mixed families throw" (overlaps "10.0.0.0/8" "::/0"))
  (fails "overlaps: invalid input throws" (overlaps "10.0.0.0/8" "foo"))

  # assertUniqueAddresses
  (case "assertUniqueAddresses returns the list"
    (assertUniqueAddresses [
      "10.0.0.1"
      "10.0.0.2/24"
      "::1"
    ])
    [
      "10.0.0.1"
      "10.0.0.2/24"
      "::1"
    ]
  )
  (case "assertUniqueAddresses of an empty list" (assertUniqueAddresses [ ]) [ ])
  (case "assertUniqueAddresses: IPv4 and IPv4-mapped IPv6 are different"
    (assertUniqueAddresses [
      "::ffff:10.0.0.1"
      "10.0.0.1"
    ])
    [
      "::ffff:10.0.0.1"
      "10.0.0.1"
    ]
  )
  (fails "assertUniqueAddresses: same address with and without mask" (assertUniqueAddresses [
    "10.0.0.1/24"
    "10.0.0.1"
  ]))
  (fails "assertUniqueAddresses: same IPv6 address spelled differently" (assertUniqueAddresses [
    "2001:db8::1"
    "::2"
    "2001:DB8:0::1/64"
  ]))
  (fails "assertUniqueAddresses: invalid address" (assertUniqueAddresses [ "foo" ]))
  (case "assertUniqueAddresses accepts distinct hashed addresses" (
    hashedNames [
      "a"
      "b"
      "c"
    ] == assertUniqueAddresses (hashedNames [
      "a"
      "b"
      "c"
    ])
  ) true)
  (fails "assertUniqueAddresses catches hashed collisions (5 names in a /30)" (
    assertUniqueAddresses (
      map
        (
          name:
          hashedAddress {
            salt = "s";
            network = "10.0.0.0/30";
            inherit name;
          }
        )
        [
          "a"
          "b"
          "c"
          "d"
          "e"
        ]
    )
  ))

  # assertNoOverlap
  (case "assertNoOverlap returns the list"
    (assertNoOverlap [
      "10.0.0.0/24"
      "10.0.1.0/24"
    ])
    [
      "10.0.0.0/24"
      "10.0.1.0/24"
    ]
  )
  (case "assertNoOverlap of an empty list" (assertNoOverlap [ ]) [ ])
  (case "assertNoOverlap of a single network" (assertNoOverlap [ "::/0" ]) [ "::/0" ])
  (fails "assertNoOverlap: nested networks" (assertNoOverlap [
    "10.0.0.0/23"
    "10.0.1.0/24"
  ]))
  (fails "assertNoOverlap: first and third overlap" (assertNoOverlap [
    "10.0.0.0/24"
    "10.1.0.0/24"
    "10.0.0.128/25"
  ]))
  (fails "assertNoOverlap: duplicate IPv6 networks" (assertNoOverlap [
    "fd00::/64"
    "FD00:0::/64"
  ]))
  (fails "assertNoOverlap: mixed families" (assertNoOverlap [
    "10.0.0.0/8"
    "fd00::/8"
  ]))
  (case "assertNoOverlap accepts distinct hashed subnets" (
    let
      subnets =
        map
          (
            name:
            hashedSubnet {
              salt = "s";
              network = "fd12:3456:789a::/48";
              inherit name;
              prefixLength = 64;
            }
          )
          [
            "a"
            "b"
            "c"
          ];
    in
    assertNoOverlap subnets == subnets
  ) true)
  (fails "assertNoOverlap catches hashed collisions (5 /64s in a /62)" (
    assertNoOverlap (
      map
        (
          name:
          hashedSubnet {
            salt = "s";
            network = "2001:db8::/62";
            inherit name;
            prefixLength = 64;
          }
        )
        [
          "a"
          "b"
          "c"
          "d"
          "e"
        ]
    )
  ))

  # isPrivate
  (case "isPrivate 10.255.255.255" (isPrivate "10.255.255.255") true)
  (case "isPrivate 11.0.0.0" (isPrivate "11.0.0.0") false)
  (case "isPrivate 172.16.0.1" (isPrivate "172.16.0.1") true)
  (case "isPrivate 172.31.255.255" (isPrivate "172.31.255.255") true)
  (case "isPrivate 172.32.0.0" (isPrivate "172.32.0.0") false)
  (case "isPrivate 172.15.255.255" (isPrivate "172.15.255.255") false)
  (case "isPrivate 192.168.0.1/24" (isPrivate "192.168.0.1/24") true)
  (case "isPrivate 192.169.0.1" (isPrivate "192.169.0.1") false)
  (case "isPrivate ignores the mask: 10.0.0.0/4" (isPrivate "10.0.0.0/4") true)
  (case "isPrivate ignores the mask: 8.8.8.8/4" (isPrivate "8.8.8.8/4") false)
  (case "isPrivate fd00::1" (isPrivate "fd00::1") true)
  (case "isPrivate fc00::" (isPrivate "fc00::") true)
  (case "isPrivate fe00::" (isPrivate "fe00::") false)
  (case "isPrivate 2001:db8::1" (isPrivate "2001:db8::1") false)
  (case "isPrivate: IPv4-mapped private address is not private" (isPrivate "::ffff:10.0.0.1") false)
  (fails "isPrivate throws for invalid input" (isPrivate "foo"))

  # isLoopback
  (case "isLoopback 127.0.0.1" (isLoopback "127.0.0.1") true)
  (case "isLoopback 127.255.255.255" (isLoopback "127.255.255.255") true)
  (case "isLoopback 128.0.0.1" (isLoopback "128.0.0.1") false)
  (case "isLoopback ::1" (isLoopback "::1") true)
  (case "isLoopback ignores the mask: ::1/64" (isLoopback "::1/64") true)
  (case "isLoopback ::2" (isLoopback "::2") false)
  (case "isLoopback ::" (isLoopback "::") false)
  (case "isLoopback ::ffff:127.0.0.1" (isLoopback "::ffff:127.0.0.1") false)
  (fails "isLoopback throws for an invalid mask" (isLoopback "1.2.3.4/33"))

  # isLinkLocal
  (case "isLinkLocal 169.254.1.1" (isLinkLocal "169.254.1.1") true)
  (case "isLinkLocal 169.255.0.0" (isLinkLocal "169.255.0.0") false)
  (case "isLinkLocal fe80::1/64" (isLinkLocal "fe80::1/64") true)
  (case "isLinkLocal febf:ffff::1" (isLinkLocal "febf:ffff::1") true)
  (case "isLinkLocal fec0::1" (isLinkLocal "fec0::1") false)
  (fails "isLinkLocal throws for invalid input" (isLinkLocal ""))

  # isULA
  (case "isULA fd12::1" (isULA "fd12::1") true)
  (case "isULA fc00::" (isULA "fc00::") true)
  (case "isULA fe80::1" (isULA "fe80::1") false)
  (case "isULA is false for IPv4" (isULA "10.0.0.1") false)
  (fails "isULA throws for invalid input" (isULA "fd00::/129"))

  # isMulticast
  (case "isMulticast 224.0.0.1" (isMulticast "224.0.0.1") true)
  (case "isMulticast 239.255.255.255" (isMulticast "239.255.255.255") true)
  (case "isMulticast 240.0.0.1" (isMulticast "240.0.0.1") false)
  (case "isMulticast 223.255.255.255" (isMulticast "223.255.255.255") false)
  (case "isMulticast ff02::1" (isMulticast "ff02::1") true)
  (case "isMulticast ff00::" (isMulticast "ff00::") true)
  (case "isMulticast fe80::" (isMulticast "fe80::") false)
  (fails "isMulticast throws for invalid input" (isMulticast "224.0.0"))

  # multicastScope
  (case "multicastScope IPv6 scopes ff00:: to ff0f::"
    (genList (i: multicastScope "ff0${toLower (toHexString i)}::1") 16)
    [
      "reserved"
      "interface"
      "link"
      "realm"
      "admin"
      "site"
      "unassigned"
      "unassigned"
      "organization"
      "unassigned"
      "unassigned"
      "unassigned"
      "unassigned"
      "unassigned"
      "global"
      "reserved"
    ]
  )
  (case "multicastScope ignores the flags: ff12::1 is link" (multicastScope "ff12::1") "link")
  (case "multicastScope ignores the flags: ff3e::8000:1 is global"
    (multicastScope "ff3e:30:2001:db8::8000:1")
    "global"
  )
  (case "multicastScope ignores the flags: fff5::1 is site" (multicastScope "fff5::1") "site")
  (case "multicastScope ff05::2" (multicastScope "ff05::2") "site")
  (case "multicastScope ff0e::" (multicastScope "ff0e::") "global")
  (case "multicastScope solicited-node" (multicastScope "ff02::1:ff12:3456") "link")
  (case "multicastScope ignores the mask" (multicastScope "ff02::1/8") "link")
  (case "multicastScope 224.0.0.251" (multicastScope "224.0.0.251") "link")
  (case "multicastScope 224.0.0.0" (multicastScope "224.0.0.0") "link")
  (case "multicastScope 224.0.0.255" (multicastScope "224.0.0.255") "link")
  (case "multicastScope 224.0.1.0" (multicastScope "224.0.1.0") "global")
  (case "multicastScope 232.1.1.1 (SSM)" (multicastScope "232.1.1.1") "global")
  (case "multicastScope 238.255.255.255" (multicastScope "238.255.255.255") "global")
  (case "multicastScope 239.0.0.0" (multicastScope "239.0.0.0") "admin")
  (case "multicastScope 239.191.255.255" (multicastScope "239.191.255.255") "admin")
  (case "multicastScope 239.192.0.0" (multicastScope "239.192.0.0") "organization")
  (case "multicastScope 239.195.255.255" (multicastScope "239.195.255.255") "organization")
  (case "multicastScope 239.196.0.0" (multicastScope "239.196.0.0") "admin")
  (case "multicastScope 239.255.255.250 (IPv4 local scope)" (multicastScope "239.255.255.250")
    "admin"
  )
  (case "multicastScope ignores the mask of IPv4" (multicastScope "224.0.0.251/4") "link")
  (case "multicastScope is null for unicast"
    (map multicastScope [
      "10.0.0.1"
      "fe80::1"
      "223.255.255.255"
      "240.0.0.0"
      "feff::"
    ])
    [
      null
      null
      null
      null
      null
    ]
  )
  (case "multicastScope is null for IPv4-mapped multicast" (multicastScope "::ffff:224.0.0.251") null)
  (fails "multicastScope throws for invalid input" (multicastScope "ff02::1::1"))

  # isLinkScope
  (case "isLinkScope link-local unicast"
    (map isLinkScope [
      "169.254.0.1"
      "fe80::1"
      "febf:ffff::1/64"
    ])
    [
      true
      true
      true
    ]
  )
  (case "isLinkScope link-scope multicast"
    (map isLinkScope [
      "224.0.0.251"
      "ff02::1"
      "ff12::1"
      "ff32::1"
      "ff02::1:ff00:1"
    ])
    [
      true
      true
      true
      true
      true
    ]
  )
  (case "isLinkScope other scopes"
    (map isLinkScope [
      "224.0.1.1"
      "ff01::1"
      "ff05::2"
      "ff0e::1"
      "fec0::1"
      "169.255.0.0"
      "10.0.0.1"
    ])
    [
      false
      false
      false
      false
      false
      false
      false
    ]
  )
  (case "isLinkScope ignores the mask" (isLinkScope "ff02::1/128") true)
  (case "isLinkScope IPv4-mapped"
    (map isLinkScope [
      "::ffff:169.254.0.1"
      "::ffff:224.0.0.251"
    ])
    [
      false
      false
    ]
  )
  (fails "isLinkScope throws for invalid input" (isLinkScope "fe80::1%eth0"))

  # isDocumentation
  (case "isDocumentation IPv4 ranges and boundaries"
    (map isDocumentation [
      "192.0.2.0"
      "192.0.2.255"
      "192.0.3.0"
      "198.51.100.1"
      "198.51.101.0"
      "203.0.113.255"
      "203.0.112.255"
      "233.252.0.1"
      "233.252.1.0"
    ])
    [
      true
      true
      false
      true
      false
      true
      false
      true
      false
    ]
  )
  (case "isDocumentation IPv6 ranges and boundaries"
    (map isDocumentation [
      "2001:db8::"
      "2001:db8:ffff:ffff::1"
      "2001:db9::"
      "3fff::"
      "3fff:fff:ffff::"
      "3fff:1000::"
      "3ffe::"
    ])
    [
      true
      true
      false
      true
      true
      false
      false
    ]
  )
  (case "isDocumentation ignores the mask"
    (map isDocumentation [
      "2001:db8::/16"
      "192.0.2.1/8"
    ])
    [
      true
      true
    ]
  )
  (case "isDocumentation IPv4-mapped" (isDocumentation "::ffff:192.0.2.1") false)
  (fails "isDocumentation throws for invalid input" (isDocumentation "192.0.2.256"))

  # isGlobal
  (case "isGlobal public unicast"
    (map isGlobal [
      "8.8.8.8"
      "1.1.1.1"
      "2001:4860:4860::8888"
      "2a00:1450::1"
      "3ffe::1"
    ])
    [
      true
      true
      true
      true
      true
    ]
  )
  (case "isGlobal non-global IPv4 blocks" (map isGlobal [
    "0.0.0.0"
    "0.255.255.255"
    "10.1.2.3"
    "100.64.0.1"
    "100.127.255.255"
    "127.0.0.1"
    "169.254.1.1"
    "172.16.0.1"
    "192.0.0.1"
    "192.0.2.1"
    "192.168.1.1"
    "198.18.0.1"
    "198.19.255.255"
    "198.51.100.1"
    "203.0.113.1"
    "240.0.0.1"
    "255.255.255.255"
  ]) (genList (_: false) 17))
  (case "isGlobal IPv4 block boundaries" (map isGlobal [
    "1.0.0.0"
    "9.255.255.255"
    "11.0.0.0"
    "100.63.255.255"
    "100.128.0.0"
    "172.15.255.255"
    "172.32.0.0"
    "198.17.255.255"
    "198.20.0.0"
    "192.88.99.1"
    "223.255.255.255"
  ]) (genList (_: true) 11))
  (case "isGlobal IPv4 exceptions inside 192.0.0.0/24"
    (map isGlobal [
      "192.0.0.8"
      "192.0.0.9"
      "192.0.0.10"
      "192.0.0.11"
      "192.0.0.170"
    ])
    [
      false
      true
      true
      false
      false
    ]
  )
  (case "isGlobal AS112 and AMT are global"
    (map isGlobal [
      "192.31.196.1"
      "192.175.48.1"
      "192.52.193.1"
      "2620:4f:8000::1"
    ])
    [
      true
      true
      true
      true
    ]
  )
  (case "isGlobal non-global IPv6 blocks" (map isGlobal [
    "::"
    "::1"
    "::ffff:8.8.8.8"
    "::8.8.8.8"
    "::ffff:0:808:808"
    "64:ff9b:1::1"
    "100::1"
    "2001::1"
    "2001:0:4136:e378::1"
    "2001:2::1"
    "2001:10::1"
    "2001:db8::1"
    "2002:808:808::1"
    "3fff::1"
    "5f00::1"
    "fc00::1"
    "fd00::1"
    "fe80::1"
    "fec0::1"
    "1fff:ffff::"
    "4000::"
  ]) (genList (_: false) 21))
  (case "isGlobal IPv6 exceptions inside 2001::/23"
    (map isGlobal [
      "2001:1::"
      "2001:1::1"
      "2001:1::2"
      "2001:1::3"
      "2001:1::4"
      "2001:3::1"
      "2001:3:ffff::1"
      "2001:4:112::1"
      "2001:4:113::1"
      "2001:1f::1"
      "2001:20::1"
      "2001:2f:ffff::1"
      "2001:30::1"
      "2001:3f::1"
      "2001:40::1"
    ])
    [
      false
      true
      true
      true
      false
      true
      true
      true
      false
      false
      true
      true
      true
      true
      false
    ]
  )
  (case "isGlobal IPv6 boundaries of 2001::/23"
    (map isGlobal [
      "2001:1ff:ffff::1"
      "2001:200::1"
      "2000:ffff::1"
    ])
    [
      false
      true
      true
    ]
  )
  (case "isGlobal NAT64 well-known prefix is global"
    (map isGlobal [
      "64:ff9b::8.8.8.8"
      "64:ff9b::1:0:0"
    ])
    [
      true
      false
    ]
  )
  (case "isGlobal multicast by scope"
    (map isGlobal [
      "ff0e::1"
      "ff1e::1"
      "ff05::2"
      "ff08::1"
      "ff02::1"
      "ff0f::1"
      "224.0.0.251"
      "224.0.1.1"
      "232.1.1.1"
      "239.1.1.1"
      "239.255.255.250"
      "233.252.0.1"
    ])
    [
      true
      true
      false
      false
      false
      false
      false
      true
      true
      false
      false
      false
    ]
  )
  (case "isGlobal ignores the mask"
    (map isGlobal [
      "10.0.0.0/0"
      "8.8.8.8/8"
      "2001:db8::/3"
      "2a00::1/16"
    ])
    [
      false
      true
      false
      true
    ]
  )
  (fails "isGlobal throws for invalid input" (isGlobal "foo"))

  # ip6.expand
  (case "ip6.expand an address" (ip6.expand "2001:db8::1") "2001:0db8:0000:0000:0000:0000:0000:0001")
  (case "ip6.expand keeps the mask and lowercases" (ip6.expand "2001:DB8::1/64")
    "2001:0db8:0000:0000:0000:0000:0000:0001/64"
  )
  (case "ip6.expand ::" (ip6.expand "::") "0000:0000:0000:0000:0000:0000:0000:0000")
  (case "ip6.expand an IPv4-mapped address" (ip6.expand "::ffff:192.0.2.1")
    "0000:0000:0000:0000:0000:ffff:c000:0201"
  )
  (case "ip6.expand a network" (ip6.expand "fe80::/10") "fe80:0000:0000:0000:0000:0000:0000:0000/10")
  (case "ip6.expand an already expanded address"
    (ip6.expand "2001:0db8:0000:0000:0000:0000:0000:0001")
    "2001:0db8:0000:0000:0000:0000:0000:0001"
  )
  (case "ip4.expand is the canonical spelling" (ip4.expand "10.0.0.1/8") "10.0.0.1/8")
  (fails "ip6.expand throws for IPv4" (ip6.expand "1.2.3.4"))
  (fails "ip6.expand throws for invalid input" (ip6.expand "foo"))

  # toArpa
  (case "toArpa IPv4 address" (toArpa "1.2.3.4") "4.3.2.1.in-addr.arpa")
  (case "toArpa IPv4 /32" (toArpa "1.2.3.4/32") "4.3.2.1.in-addr.arpa")
  (case "toArpa IPv4 /24" (toArpa "192.168.5.0/24") "5.168.192.in-addr.arpa")
  (case "toArpa IPv4 /16" (toArpa "10.1.0.0/16") "1.10.in-addr.arpa")
  (case "toArpa ignores device bits" (toArpa "10.1.2.3/16") "1.10.in-addr.arpa")
  (case "toArpa IPv4 /8" (toArpa "10.0.0.0/8") "10.in-addr.arpa")
  (case "toArpa IPv4 /0" (toArpa "0.0.0.0/0") "in-addr.arpa")
  (fails "toArpa throws for a non-octet-aligned IPv4 mask" (toArpa "10.0.0.0/12"))
  (case "toArpa IPv6 address" (toArpa "2001:db8::1")
    "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa"
  )
  (case "toArpa IPv4-mapped address" (toArpa "::ffff:1.2.3.4")
    "4.0.3.0.2.0.1.0.f.f.f.f.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa"
  )
  (case "toArpa IPv6 /32" (toArpa "2001:db8::/32") "8.b.d.0.1.0.0.2.ip6.arpa")
  (case "toArpa IPv6 /36" (toArpa "2001:db8::/36") "0.8.b.d.0.1.0.0.2.ip6.arpa")
  (case "toArpa IPv6 /48" (toArpa "2001:db8::/48") "0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa")
  (case "toArpa IPv6 /64" (toArpa "2001:DB8:ABCD:12::/64") "2.1.0.0.d.c.b.a.8.b.d.0.1.0.0.2.ip6.arpa")
  (case "toArpa IPv6 /0" (toArpa "::/0") "ip6.arpa")
  (fails "toArpa throws for a non-nibble-aligned IPv6 mask" (toArpa "2001:db8::/30"))
  (fails "toArpa throws for invalid input" (toArpa "foo"))

  # eui64FromMac
  (case "eui64FromMac flips the U/L bit and inserts ff:fe" (eui64FromMac {
    network = "2001:db8::/64";
    mac = "52:54:00:12:34:56";
  }) "2001:db8::5054:ff:fe12:3456")
  (case "eui64FromMac sets the U/L bit" (eui64FromMac {
    network = "fe80::/64";
    mac = "00:1a:2b:3c:4d:5e";
  }) "fe80::21a:2bff:fe3c:4d5e")
  (case "eui64FromMac clears the U/L bit" (eui64FromMac {
    network = "fe80::/64";
    mac = "02:00:00:00:00:01";
  }) "fe80::ff:fe00:1")
  (case "eui64FromMac ignores device bits of the network" (eui64FromMac {
    network = "2001:db8:1:2::99/64";
    mac = "52:54:00:12:34:56";
  }) "2001:db8:1:2:5054:ff:fe12:3456")
  (fails "eui64FromMac throws for a /48" (eui64FromMac {
    network = "2001:db8::/48";
    mac = "52:54:00:12:34:56";
  }))
  (fails "eui64FromMac throws for a network without mask" (eui64FromMac {
    network = "2001:db8::";
    mac = "52:54:00:12:34:56";
  }))
  (fails "eui64FromMac throws for IPv4" (eui64FromMac {
    network = "10.0.0.0/24";
    mac = "52:54:00:12:34:56";
  }))
  (fails "eui64FromMac throws for an invalid MAC" (eui64FromMac {
    network = "fe80::/64";
    mac = "zz:54:00:12:34:56";
  }))

  # compareAddresses
  (case "compareAddresses compares numerically" (compareAddresses "10.0.0.2" "10.0.0.10") (-1))
  (case "compareAddresses greater" (compareAddresses "10.0.0.10" "10.0.0.2") 1)
  (case "compareAddresses equal" (compareAddresses "10.0.0.1" "10.0.0.1") 0)
  (case "compareAddresses: no mask equals full mask" (compareAddresses "10.0.0.1/32" "10.0.0.1") 0)
  (case "compareAddresses: shorter mask first" (compareAddresses "10.0.0.0/8" "10.0.0.0/16") (-1))
  (case "compareAddresses: IPv4 before IPv6" (compareAddresses "255.255.255.255" "::") (-1))
  (case "compareAddresses: IPv6 after IPv4" (compareAddresses "::" "0.0.0.0") 1)
  (case "compareAddresses: IPv4-mapped IPv6 after IPv4"
    (compareAddresses "::ffff:10.0.0.1" "10.0.0.1")
    1
  )
  (case "compareAddresses: spelling does not matter" (compareAddresses "2001:DB8::1" "2001:db8::1") 0)
  (case "compareAddresses: IPv6 by value" (compareAddresses "2001:db8::2" "2001:db8::1:0") (-1))
  (fails "compareAddresses throws for invalid input" (compareAddresses "foo" "1.2.3.4"))

  # sortAddresses
  (case "sortAddresses"
    (sortAddresses [
      "::1"
      "10.0.0.10"
      "10.0.0.2"
      "2001:db8::"
      "10.0.0.2/24"
      "9.255.255.255"
    ])
    [
      "9.255.255.255"
      "10.0.0.2/24"
      "10.0.0.2"
      "10.0.0.10"
      "::1"
      "2001:db8::"
    ]
  )
  (case "sortAddresses of an empty list" (sortAddresses [ ]) [ ])
  (fails "sortAddresses throws for a single invalid address" (sortAddresses [ "foo" ]))
  (fails "sortAddresses throws for an invalid address" (sortAddresses [
    "1.2.3.4"
    "foo"
  ]))

  # special-purpose constants
  (case "ip4.special entries are normalized IPv4 networks in canonical spelling" (filter (
    n: !(ip4.checkNormalizedNetwork n && ip4.checkCanonical n && hasInfix "/" n)
  ) (attrValues ip4.special)) [ ])
  (case "ip6.special entries are normalized IPv6 networks in canonical spelling" (filter (
    n: !(ip6.checkNormalizedNetwork n && ip6.checkCanonical n && hasInfix "/" n)
  ) (attrValues ip6.special)) [ ])
  (case "ip4.special values"
    (with ip4.special; [
      private172
      sharedAddressSpace
      documentation2
      ietfProtocolAssignments
      limitedBroadcast
    ])
    [
      "172.16.0.0/12"
      "100.64.0.0/10"
      "198.51.100.0/24"
      "192.0.0.0/24"
      "255.255.255.255/32"
    ]
  )
  (case "ip6.special values"
    (with ip6.special; [
      documentation
      ipv4Mapped
      nat64
      uniqueLocal
      multicast
    ])
    [
      "2001:db8::/32"
      "::ffff:0.0.0.0/96"
      "64:ff9b::/96"
      "fc00::/7"
      "ff00::/8"
    ]
  )
  (case "ip6.special.ipv4Mapped contains IPv4-mapped addresses"
    (inSubnet "::ffff:192.0.2.1" ip6.special.ipv4Mapped)
    true
  )
  (case "ip6.special.ipv4Mapped spelled as ::ffff:0:0/96" (canonical "::ffff:0:0/96")
    ip6.special.ipv4Mapped
  )
  (case "special entries are only nested in container blocks" (concatMap
    (
      family:
      let
        special = family.special;
        names = attrNames special;
      in
      concatMap (
        a:
        concatMap (
          b:
          optional (
            a != b && subnetRelation special.${a} special.${b} == "subset" && !(elem b family.containers)
          ) "${a} in ${b}"
        ) names
      ) names
    )
    [
      {
        inherit (ip4) special;
        containers = [
          "reserved"
          "ietfProtocolAssignments"
          "multicast"
          "adminScoped"
        ];
      }
      {
        inherit (ip6) special;
        containers = [
          "globalUnicast"
          "ietfProtocolAssignments"
          "multicast"
          "linkLocalMulticast"
        ];
      }
    ]
  ) [ ])
  (case "nested special entries lie within their container" (
    with ip4.special;
    map (pair: subnetRelation (elemAt pair 0) (elemAt pair 1)) [
      [
        limitedBroadcast
        reserved
      ]
      [
        pcpAnycast
        ietfProtocolAssignments
      ]
      [
        turnAnycast
        ietfProtocolAssignments
      ]
      [
        localNetworkControl
        multicast
      ]
      [
        mcastTestNet
        multicast
      ]
      [
        organizationLocal
        adminScoped
      ]
      [
        localScope
        adminScoped
      ]
    ]
    ++ (
      with ip6.special;
      map (pair: subnetRelation (elemAt pair 0) (elemAt pair 1)) [
        [
          ietfProtocolAssignments
          globalUnicast
        ]
        [
          documentation2
          globalUnicast
        ]
        [
          as112DirectDelegation
          globalUnicast
        ]
        [
          teredo
          ietfProtocolAssignments
        ]
        [
          dnsSdSrpAnycast
          ietfProtocolAssignments
        ]
        [
          droneRemoteId
          ietfProtocolAssignments
        ]
        [
          solicitedNode
          linkLocalMulticast
        ]
        [
          linkLocalMulticast
          multicast
        ]
      ]
    )
  ) (genList (_: "subset") 15))
  (case "new ip4.special values"
    (with ip4.special; [
      pcpAnycast
      turnAnycast
      as112
      amt
      as112DirectDelegation
      localNetworkControl
      mcastTestNet
      adminScoped
      organizationLocal
      localScope
    ])
    [
      "192.0.0.9/32"
      "192.0.0.10/32"
      "192.31.196.0/24"
      "192.52.193.0/24"
      "192.175.48.0/24"
      "224.0.0.0/24"
      "233.252.0.0/24"
      "239.0.0.0/8"
      "239.192.0.0/14"
      "239.255.0.0/16"
    ]
  )
  (case "new ip6.special values"
    (with ip6.special; [
      ipv4Translated
      globalUnicast
      teredo
      pcpAnycast
      turnAnycast
      dnsSdSrpAnycast
      benchmarking
      amt
      as112
      orchidV2
      droneRemoteId
      as112DirectDelegation
      srv6Sid
      linkLocalMulticast
      solicitedNode
    ])
    [
      "::ffff:0:0:0/96"
      "2000::/3"
      "2001::/32"
      "2001:1::1/128"
      "2001:1::2/128"
      "2001:1::3/128"
      "2001:2::/48"
      "2001:3::/32"
      "2001:4:112::/48"
      "2001:20::/28"
      "2001:30::/28"
      "2620:4f:8000::/48"
      "5f00::/16"
      "ff02::/16"
      "ff02::1:ff00:0/104"
    ]
  )
  (case "ip6.special.ipv4Translated contains ::ffff:0:a.b.c.d but not IPv4-mapped addresses"
    (map (a: inSubnet a ip6.special.ipv4Translated) [
      "::ffff:0:c000:201"
      "::ffff:192.0.2.1"
    ])
    [
      true
      false
    ]
  )
  (case "ip6.special.solicitedNode boundaries"
    (map (a: inSubnet a ip6.special.solicitedNode) [
      "ff02::1:ff00:0"
      "ff02::1:ffff:ffff"
      "ff02::1:fe00:0"
      "ff02::2:ff00:0"
      "ff12::1:ff00:1"
    ])
    [
      true
      true
      false
      false
      false
    ]
  )
  (case "ip6.special.srv6Sid / globalUnicast boundaries"
    (map (pair: inSubnet (elemAt pair 0) (elemAt pair 1)) (
      with ip6.special;
      [
        [
          "5f00::1"
          srv6Sid
        ]
        [
          "5f01::"
          srv6Sid
        ]
        [
          "5eff::"
          srv6Sid
        ]
        [
          "2000::"
          globalUnicast
        ]
        [
          "3fff:ffff::"
          globalUnicast
        ]
        [
          "1fff::"
          globalUnicast
        ]
        [
          "4000::"
          globalUnicast
        ]
      ]
    ))
    [
      true
      false
      false
      true
      true
      false
      false
    ]
  )
  (case "ip4.special AS112 / AMT boundaries"
    (map (pair: inSubnet (elemAt pair 0) (elemAt pair 1)) (
      with ip4.special;
      [
        [
          "192.31.196.255"
          as112
        ]
        [
          "192.31.197.0"
          as112
        ]
        [
          "192.175.48.0"
          as112DirectDelegation
        ]
        [
          "192.175.47.255"
          as112DirectDelegation
        ]
        [
          "192.52.193.1"
          amt
        ]
        [
          "192.52.192.255"
          amt
        ]
      ]
    ))
    [
      true
      false
      true
      false
      true
      false
    ]
  )
  (case "IETF protocol assignment blocks contain the nested assignments"
    (
      map (a: inSubnet a ip4.special.ietfProtocolAssignments) [
        "192.0.0.9"
        "192.0.0.170"
      ]
      ++ map (a: inSubnet a ip6.special.ietfProtocolAssignments) [
        "2001:0:4136::1"
        "2001:1::1"
      ]
    )
    [
      true
      true
      true
      true
    ]
  )
  # NAT64 (RFC 6052 2.4 examples, all embedding 192.0.2.33)
  (case "nat64Address follows the RFC 6052 examples for every prefix length"
    (map
      (
        prefix:
        nat64Address {
          inherit prefix;
          address = "192.0.2.33";
        }
      )
      [
        "2001:db8::/32"
        "2001:db8:100::/40"
        "2001:db8:122::/48"
        "2001:db8:122:300::/56"
        "2001:db8:122:344::/64"
        "2001:db8:122:344::/96"
      ]
    )
    [
      "2001:db8:c000:221::"
      "2001:db8:1c0:2:21::"
      "2001:db8:122:c000:2:2100::"
      "2001:db8:122:3c0:0:221::"
      "2001:db8:122:344:c0:2:2100:0"
      "2001:db8:122:344::c000:221"
    ]
  )
  (case "nat64Extract inverts the RFC 6052 examples"
    (map
      (
        p:
        nat64Extract {
          prefix = elemAt p 0;
          address = elemAt p 1;
        }
      )
      [
        [
          "2001:db8::/32"
          "2001:db8:c000:221::"
        ]
        [
          "2001:db8:100::/40"
          "2001:db8:1c0:2:21::"
        ]
        [
          "2001:db8:122::/48"
          "2001:db8:122:c000:2:2100::"
        ]
        [
          "2001:db8:122:300::/56"
          "2001:db8:122:3c0:0:221::"
        ]
        [
          "2001:db8:122:344::/64"
          "2001:db8:122:344:c0:2:2100:0"
        ]
        [
          "2001:db8:122:344::/96"
          "2001:db8:122:344::192.0.2.33"
        ]
      ]
    )
    [
      "192.0.2.33"
      "192.0.2.33"
      "192.0.2.33"
      "192.0.2.33"
      "192.0.2.33"
      "192.0.2.33"
    ]
  )
  (case "nat64Address defaults to the well-known prefix" (nat64Address {
    address = "192.0.2.33";
  }) "64:ff9b::c000:221")
  (case "nat64Extract defaults to the well-known prefix" (nat64Extract {
    address = "64:ff9b::192.0.2.33";
  }) "192.0.2.33")
  (case "nat64Address ignores the mask of the IPv4 address" (nat64Address {
    address = "192.0.2.33/24";
  }) "64:ff9b::c000:221")
  (fails "nat64Address refuses the well-known prefix for private addresses (RFC 6052 3.1)"
    (nat64Address {
      address = "10.0.0.1";
    })
  )
  (fails "nat64Address refuses the well-known prefix for shared address space" (nat64Address {
    address = "100.64.0.1";
  }))
  (case "nat64Address' returns null for the well-known prefix with private addresses" (nat64Address' {
    address = "192.168.1.1";
  }) null)
  (case "nat64Address allows private addresses with the local-use prefix" (nat64Address {
    prefix = ip6.special.nat64Local;
    address = "10.0.0.1";
  }) "64:ff9b:1:a00:0:100::")
  (fails "nat64Address throws for invalid prefix lengths" (nat64Address {
    prefix = "2001:db8::/80";
    address = "192.0.2.33";
  }))
  (fails "nat64Address throws for invalid IPv4 addresses" (nat64Address {
    address = "2001:db8::1";
  }))
  (case "nat64Extract' returns null outside of the prefix" (nat64Extract' {
    address = "2001:db8::c000:221";
  }) null)
  (case "nat64Extract' returns null for a non-zero u octet" (nat64Extract' {
    prefix = "2001:db8::/32";
    address = "2001:db8:c000:221:100::";
  }) null)
  (fails "nat64Extract throws outside of the prefix" (nat64Extract {
    address = "2001:db8::c000:221";
  }))
  (case "checkNat64Prefix"
    (map checkNat64Prefix [
      "64:ff9b::/96"
      "64:ff9b:1::/48"
      "2001:db8::/32"
      "2001:db8::/80"
      "2001:db8::1/96"
      "2001:db8:0:0:100::/96"
      "64:ff9b::"
      "192.0.2.0/24"
      42
    ])
    [
      true
      true
      true
      false
      false
      false
      false
      false
      false
    ]
  )
  (case "nat64Address / nat64Extract round trip for a /40 over many addresses" (all
    (
      a:
      nat64Extract {
        prefix = "2001:db8:100::/40";
        address = nat64Address {
          prefix = "2001:db8:100::/40";
          address = a;
        };
      } == a
    )
    [
      "0.0.0.0"
      "1.2.3.4"
      "192.0.2.33"
      "203.0.113.255"
      "255.255.255.255"
    ]
  ) true)

  (case "inSubnet with special constants"
    (map (a: inSubnet a ip4.special.sharedAddressSpace) [
      "100.64.0.1"
      "100.128.0.1"
    ])
    [
      true
      false
    ]
  )
]
