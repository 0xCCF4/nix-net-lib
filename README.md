# Nix network library
A nix library for parsing, validating and manipulating IPv4 and IPv6 addresses.

## Features
- **Parse** IPv4 and IPv6 addresses in CIDR notation (e.g., `192.168.1.1/24`, `2001:db8::1/64`)
- **Decompose** addresses into network, device, mask, and integer components
- **Compose** string addresses from integer parts and mask values
- **Validate** IPv4/6 addresses, networks, endpoints (`[2001:db8::1]:53`), MAC addresses and netmasks
- **Type support** for NixOS modules and options
- **IPv6 compression support** use of compression operator `::` supported, output is canonical (RFC 5952)
- **IPv4-mapped IPv6** addresses like `::ffff:1.2.3.4` are parsed and rendered in dotted form (RFC 5952 §5). Zone IDs (`fe80::1%eth0`) are not supported.
- **Allocate** addresses and subnets by index or derived from names (hashing), check host ranges, classify addresses, build reverse DNS names

## Breaking changes
- **`assignAddress` / `assignAddress'` return the address without mask**, like `hashedAddress`
  (`assignAddress "10.0.0.0/16" 5` is now `"10.0.0.5"`, was `"10.0.0.5/16"`). NixOS options usually
  take the address and the prefix length separately (e.g. `networking.interfaces.<name>.ipv4.addresses`),
  so the bare address is what is needed most of the time. If you need the mask, append it:
  ```nix
  "${lib.net.assignAddress net 5}/${toString (lib.net.decompose net).mask}"
  ```
- **`laysWithinSubnet` is renamed to `inSubnet`** (and `laysWithinSubnet'` to `inSubnet'`). The old
  names remain as deprecated aliases.
- **`lib.nix` no longer defaults to `<nixpkgs>`**: when importing it directly, pass a nixpkgs `lib`:
  `import ./lib.nix { inherit lib; }`.
- The flake input is now `nixpkgs-lib` (`github:nix-community/nixpkgs.lib`) instead of `nixpkgs`.

## Usage

Import the library in your Nix flake:

```nix
inputs = {
    nix-net-lib.url = "github:0xCCF4/nix-net-lib";
    # optional, share the nixpkgs library with your other inputs
    nix-net-lib.inputs.nixpkgs-lib.follows = "nixpkgs";
};
```

The library can then be used in several ways:

**Directly**, e.g. in `flake.nix` or anywhere you have access to the flake input:

```nix
nix-net-lib.lib.assignAddress "10.0.0.0/24" 5 # "10.0.0.5"
nix-net-lib.lib.types.ip4                     # option type
```

**With [flake-parts](https://flake.parts)**: pass the extended library as `specialArgs.lib`. All
flake-parts modules, including `perSystem`, then get `lib.net` / `lib.types.net`, and
`lib.nixosSystem` builds NixOS systems whose modules get it too:

```nix
outputs = inputs@{ flake-parts, nixpkgs, nix-net-lib, ... }:
  flake-parts.lib.mkFlake
    {
      inherit inputs;
      specialArgs.lib = nixpkgs.lib.extend nix-net-lib.libOverlay;
    }
    ({ lib, ... }: {
      systems = [ "x86_64-linux" ];

      perSystem = { lib, ... }: {
        # lib.net is available here as well
      };

      flake.nixosConfigurations.host = lib.nixosSystem {
        modules = [
          ({ lib, ... }: {
            options.serverIp = lib.mkOption { type = lib.types.net.ip4; };
          })
        ];
      };
    });
```

**In NixOS modules via `lib.net` / `lib.types.net`**: extend the nixpkgs library with `libOverlay`
and build the system with it, so the `lib` module argument contains the library:

```nix
outputs = { nixpkgs, nix-net-lib, ... }: {
  nixosConfigurations.host = (nixpkgs.lib.extend nix-net-lib.libOverlay).nixosSystem {
    modules = [
      ({ lib, ... }: {
        options.serverIp = lib.mkOption { type = lib.types.net.ip4; };
        config.networking.defaultGateway = lib.net.firstHost "192.168.1.0/24";
      })
    ];
  };
};
```

**In NixOS modules via the `netLib` module argument**: import as NixOS module; it makes the
library available as `netLib`:

```nix
# in your configuration
imports = [ nix-net-lib.nixosModules.default ];

# in any module
{ lib, netLib, ... }: {
  options.serverIp = lib.mkOption { type = netLib.types.ip4; };
}
```

**In `pkgs.lib`** via the nixpkgs overlay:

```nix
nixpkgs.overlays = [ nix-net-lib.overlays.default ];
# pkgs.lib.net.inSubnet ..., pkgs.lib.types.net.ip4
```

Note that the overlay **only changes `pkgs.lib`, not the `lib` module argument** of NixOS modules
(that one is fixed by `nixosSystem`). Using `lib.net` in a module after only adding the overlay
fails, use one of the two module approaches above instead.

Without flakes, import `lib.nix` and pass a nixpkgs library: `import ./lib.nix { inherit lib; }`.

## Example: Decomposing an IPv6 Address

```nix
lib.net.decompose "fe80::11/64" # or lib.net.ip6.decompose
# Returns (plus `_meta` describing the address family):
{
    address = "fe80::11/64";
    addressNoMask = "fe80::11";
    addressParts = [ 65152 0 0 0 0 0 0 17 ];

    device = "::11/64";
    deviceNoMask = "::11";
    deviceParts = [ 0 0 0 0 0 0 0 17 ];

    network = "fe80::/64";
    networkNoMask = "fe80::";
    networkParts = [ 65152 0 0 0 0 0 0 0 ];

    networkMask = "ffff:ffff:ffff:ffff::/64";
    networkMaskNoMask = "ffff:ffff:ffff:ffff::";
    networkMaskParts = [ 65535 65535 65535 65535 0 0 0 0 ];

    mask = 64;
}
```

## Example: Validating an IPv4 Address
```nix
lib.net.ip4.check "1.2.3d.4/12" # --> false
```

## Example: NixOS option integration
```nix
options = {
    serverIp = lib.mkOption {
        type = lib.types.net.ip4; # accept any valid IPv4 address, mask optional
        description = "Server ip address";
    };
    lanHost = lib.mkOption {
        type = lib.types.net.ip4WithinNetwork "192.168.1.0/24"; # e.g. "192.168.1.20"
        description = "Address of a host in the LAN";
    };
};
```

## Example: Calculating a network address from index
```nix
lib.net.assignAddress "10.0.0.0/16" 300 # "10.0.1.44"
```

## Example: Deriving addresses and subnets from names
Hand out stable subnets and addresses without keeping a list of them, e.g. one /64 per
network out of a ULA /48 and one address per device in it:

```nix
let
  salt = "<some value>"; # e.g. openssl rand -hex 32
  network = lib.net.hashedSubnet { inherit salt; network = "fd12:3456:789a::/48"; name = "office"; prefixLength = 64; };
  # "fd12:3456:789a:xxxx::/64"
in
lib.net.hashedAddress { inherit salt network; name = "printer"; }
# "fd12:3456:789a:xxxx:xxxx:xxxx:xxxx:xxxx"
```

The free bits (the subnet ID, respectively the device part) are taken from a SHA-256 hash of the
salt and the name, so the same inputs always give the same result. Works for IPv4 and IPv6 and any mask.

Distinct names may collide, especially in small network configurations, e.g. /30 ip4 :). Wrap the results in
`assertNoOverlap` / `assertUniqueAddresses` so a collision fails the evaluation instead of
silently producing a broken network config:

```nix
with lib.net;
let
  salt = "example-salt";
  site = "fd12:3456:789a::/48";

  subnet = name: hashedSubnet { inherit salt name; network = site; prefixLength = 64; };
  lan = subnet "lan";     # "fd12:3456:789a:1e82::/64"
  iot = subnet "iot";     # "fd12:3456:789a:6c78::/64"
  guest = subnet "guest"; # "fd12:3456:789a:d003::/64"

  host = name: hashedAddress { inherit salt name; network = lan; };
  printer = host "printer"; # "fd12:3456:789a:1e82:ee46:4bf8:17cd:ecd1"
  nas = host "nas";         # "fd12:3456:789a:1e82:3e71:faad:a344:4291"
  server = host "server";   # "fd12:3456:789a:1e82:d844:331:8c78:6afa"
in
builtins.seq (assertNoOverlap [ lan iot guest ])
  (builtins.seq (assertUniqueAddresses [ printer nas server ]) {
    inherit lan iot guest printer nas server;
  })
```

Nix is lazy: a check whose result is never used never runs. `builtins.seq` forces the checks
before the addresses are handed out, so using any of them fails on a collision.

In a NixOS module,
`assertions = [ { assertion = assertUniqueAddresses [ printer nas server ] != [ ]; message = "…"; } ]`
does the same.

## Example: NAT64
`nat64Address` / `nat64Extract` embed and extract IPv4 addresses under a NAT64 prefix
(RFC 6052, all prefix lengths), e.g. to know under which IPv6 address IPv6-only hosts reach an
IPv4 host through the NAT64:

```nix
lib.net.nat64Address { address = "192.0.2.33"; }                               # "64:ff9b::c000:221"
lib.net.nat64Address { prefix = "2001:db8:64::/96"; address = "198.51.100.7"; } # "2001:db8:64::c633:6407"
lib.net.nat64Extract { address = "64:ff9b::c000:221"; }                        # "192.0.2.33"
```

Using the well-known prefix `64:ff9b::/96` with private IPv4 addresses is forbidden by RFC 6052
3.1, `nat64Address` throws for it; use a network-specific prefix such as
`ip6.special.nat64Local` (`64:ff9b:1::/48`) instead.

## Example: Reverse DNS
`toArpa` gives the reverse zone of a network and the PTR name of an address:

```nix
lib.net.toArpa "192.168.5.0/24"        # "5.168.192.in-addr.arpa"   (zone)
lib.net.toArpa "192.168.5.10"          # "10.5.168.192.in-addr.arpa" (PTR name)
lib.net.toArpa "2001:db8:abcd:12::/64" # "2.1.0.0.d.c.b.a.8.b.d.0.1.0.0.2.ip6.arpa"
```

Note: the mask must be a multiple of 8 (IPv4) or 4 (IPv6).

## API Reference
See [lib.nix](lib.nix) for the full documentation.

### NixOS Option Types
With `libOverlay` (or the nixpkgs overlay for `pkgs.lib`) types are available as `lib.types.net.XXX`,
otherwise as `nix-net-lib.lib.types.XXX` or `netLib.types.XXX`.

For each of the families `ip` (IPv4 or IPv6), `ip4` and `ip6`:

| Type                                                   | Description                                                                                       |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `ip`, `ip4`, `ip6`                                     | Any valid address in CIDR notation, mask optional                                                 |
| `ipNetwork`, `ip4Network`, `ip6Network`                | Normalized network (address + mask, no device bits set), e.g. `10.0.0.0/8`                        |
| `ipNoMask`, `ip4NoMask`, `ip6NoMask`                   | Address without trailing `/mask`, any spelling                                                    |
| `ipExplicitMask`, `ip4ExplicitMask`, `ip6ExplicitMask` | Address with explicit `/mask`, any spelling                                                       |
| `ipCanonical`, `ip4Canonical`, `ip6Canonical`          | Address in canonical spelling (RFC 5952 for IPv6), mask optional                                  |
| `ip{,4,6}WithinNetwork <network>`                      | Address within the given network; it may have a longer mask, a missing mask counts as /32 or /128 |
| `ip{,4,6}WithinNetworkStrict <network>`                | Address within the given network with exactly the same mask                                       |

Other types:

| Type               | Description                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------- |
| `port`             | Port number (same as `lib.types.port`)                                                        |
| `privilegedPort`   | Port 0–1023, binding needs root or `CAP_NET_BIND_SERVICE` on Linux                            |
| `unprivilegedPort` | Port 1024–65535                                                                               |
| `wellKnownPort`    | IANA system port, 0–1023 (RFC 6335)                                                           |
| `registeredPort`   | IANA user port, 1024–49151 (RFC 6335)                                                         |
| `dynamicPort`      | IANA dynamic/ephemeral port, 49152–65535 (RFC 6335)                                           |
| `endpoint`         | IPv4 or IPv6 endpoint, `"1.2.3.4:53"` or `"[2001:db8::1]:53"`                                 |
| `ip4Endpoint`      | IPv4 endpoint, `"1.2.3.4:53"`                                                                 |
| `ip6Endpoint`      | IPv6 endpoint, `"[2001:db8::1]:53"`                                                           |
| `mac`              | MAC address, six hex byte pairs separated by `:` or `-`                                       |
| `nat64Prefix`      | NAT64 prefix: IPv6 network of length 32, 40, 48, 56, 64 or 96 with bits 64–71 zero (RFC 6052) |
| `ip4Netmask`       | Contiguous IPv4 netmask, e.g. `"255.255.255.0"`                                               |
| `ip4PrefixLength`  | Integer between 0 and 32                                                                      |
| `ip6PrefixLength`  | Integer between 0 and 128                                                                     |

The `WithinNetwork` types are constructors taking the network; an invalid network (or one of the
wrong family) throws when the type is used:

```nix
options.lanHost = lib.mkOption { type = lib.types.net.ip4WithinNetwork "192.168.1.0/24"; };
# accepts "192.168.1.20", "192.168.1.0/25"; rejects "192.168.2.1", "192.168.0.0/16"
options.wanAddress = lib.mkOption { type = lib.types.net.ip6WithinNetworkStrict "2001:db8::/64"; };
# accepts "2001:db8::1/64"; rejects "2001:db8::1" (/128)
```

### Function reference
With `libOverlay` (or the nixpkgs overlay for `pkgs.lib`) functions are available as `lib.net.XXX`,
otherwise as `nix-net-lib.lib.XXX` or `netLib.XXX`.

Most functions come in two variants: `name'` returns `null` (or `false`) on invalid input, `name`
throws. `ipX` stands for `ip4` or `ip6`. All functions accept any valid spelling and return the
canonical one.

#### Parsing & validation

### `decompose'`
Decomposes an IPv4 or IPv6 address (the family is detected) into its components. Returns `null` if invalid.
`ipX.decompose'` does the same for a fixed family.

- **Type:** `String -> { ... } | null`
- **Example:** `decompose' "192.168.1.1/24"`
- **Return value** (an address without mask has mask 32 or 128):
    - `addressParts`: List of integers for the full IP address.
    - `address`: Normalized IP address in CIDR notation.
    - `addressNoMask`: IP address without mask.
    - `networkParts`: Integers for the network part.
    - `network`: Network part as string, e.g. `"192.168.1.0/24"`.
    - `networkNoMask`: Network part without mask.
    - `deviceParts`: Integers for the device part.
    - `device`: Device part as string, e.g. `"0.0.0.1/24"`.
    - `deviceNoMask`: Device part without mask.
    - `networkMaskParts`: Network mask parts.
    - `networkMask`: Network mask as string, e.g. `"255.255.255.0/24"`.
    - `networkMaskNoMask`: Network mask without mask notation, e.g. `"255.255.255.0"`.
    - `mask`: CIDR mask as integer.
    - `_meta`: Information about the address family (`_meta.name` is `"ip4"` or `"ip6"`).

---

### `decompose`
Like `decompose'`, but throws on invalid input. Also available as `ipX.decompose`.

- **Type:** `String -> { ... }`
- **Example:** `decompose "192.168.1.1/24"`

---

### `ip'`
Returns the interface (`ip4` or `ip6`) matching an address, or `null` if invalid.

- **Type:** `String -> { ... } | null`
- **Example:** `(ip' "::1").meta.name # "ip6"`

---

### `ip`
Like `ip'`, but throws on invalid input.

- **Type:** `String -> { ... }`
- **Example:** `(ip "10.0.0.1").decompose "10.0.0.1/8"`

---

### `ipX.check`
Checks if a string is a valid IP address in CIDR notation, mask optional.
Accepts IPv4 dotted quads without leading zeros, all IPv6 text forms of RFC 4291 2.2 (including an embedded IPv4 address like `::ffff:192.0.2.1`), and masks of 0 to 32 (IPv4) or 0 to 128 (IPv6). Zone IDs (`fe80::1%eth0`) are rejected.

- **Type:** `String -> Bool`
- **Example:** `ip4.check "192.168.1.1/24" # true`

---

### `ipX.checkNoMask`
Checks if a string is a valid IP address without a mask, in any spelling.

- **Type:** `String -> Bool`
- **Example:** `ip6.checkNoMask "2001:DB8:0::1" # true`

---

### `ipX.checkWithMask`
Checks if a string is a valid IP address with an explicit mask, in any spelling.

- **Type:** `String -> Bool`
- **Example:** `ip4.checkWithMask "192.168.1.1/24" # true`

---

### `ipX.checkCanonical`
Checks if a string is a valid IP address in its canonical spelling (RFC 5952 for IPv6), mask optional.

- **Type:** `String -> Bool`
- **Example:** `ip6.checkCanonical "2001:DB8:0::1" # false`

---

### `ipX.checkNormalizedNetwork`
Checks if a string is a normalized network address (no device bits set).

- **Type:** `String -> Bool`
- **Example:** `ip4.checkNormalizedNetwork "192.168.1.6/24" # false, since .6`

---

### `ipX.checkIpParts`
Checks if a list of integers is a valid IP address.

- **Type:** `[ Int ] -> Bool`
- **Example:** `ip4.checkIpParts [192 168 1 1] # true`

---

### `ipX.checkIpMask`
Checks if an integer is a valid CIDR mask.

- **Type:** `Int -> Bool`
- **Example:** `ip4.checkIpMask 24 # true`

#### Subnet relations

### `subnetRelation'`
Returns the network relation between two IP addresses, read as "a is _result_ to/of b": `"superset"`, `"equal"`, `"subset"`, `"disjoint"`, or `null` if invalid or of different families.

- **Type:** `String -> String -> String | null`
- **Example:** `subnetRelation' "1.2.3.4/24" "1.2.0.0/16" # "subset"`

---

### `subnetRelation`
Like `subnetRelation'`, but throws on invalid input.

- **Type:** `String -> String -> String`
- **Example:** `subnetRelation "1.2.3.4/16" "1.2.0.0/16" # "equal"`

---

### `inSubnet'`
Checks if an IP address is within a subnet (its mask may be longer). `false` on invalid input or different families.

- **Type:** `String -> String -> Bool`
- **Example:** `inSubnet' "10.1.2.3" "10.0.0.0/8" # true`

---

### `inSubnet`
Like `inSubnet'`, but throws on invalid input.

- **Type:** `String -> String -> Bool`
- **Example:** `inSubnet "fd00::1/64" "fd00::/8" # true`

---

### `laysWithinSubnet'`, `laysWithinSubnet`
Deprecated aliases of `inSubnet'` and `inSubnet`.

---

### `overlaps`
Checks whether two networks share at least one address. Throws on invalid input or different families.

- **Type:** `String -> String -> Bool`
- **Example:** `overlaps "10.0.0.0/8" "10.1.0.0/16" # true`

#### Address allocation

### `assignAddress'`
Calculates the n-th address in the given subnet, without mask. Returns `null` on invalid input or if the index is too large for the subnet.

- **Type:** `String -> Int -> String | null`
- **Example:** `assignAddress' "10.10.0.0/16" 500 # "10.10.1.244"`

---

### `assignAddress`
Like `assignAddress'`, but throws on invalid input or if the index is too large for the subnet.

- **Type:** `String -> Int -> String`
- **Example:** `assignAddress "fe80::/64" 2 # "fe80::2"`

---

### `hashedAddress`
Derives a stable address (without mask) for a device from its name inside an IPv4 or IPv6 network: all device
bits are taken from SHA-256(`salt` + ":address:" + `name`). The result may collide with other
names or be an address with a special meaning (e.g. the network address) in small networks.

- **Type:** `{ salt : String, network : String, name : String } -> String`
- **Example:** `hashedAddress { salt = "s"; network = "2001:db8::/64"; name = "host-a"; } # "2001:db8::f0a3:42e6:b7cf:1582"`

---

### `hashedSubnet`
Derives a stable subnet for a name out of a larger IPv4 or IPv6 network: the bits between the
network's mask and `prefixLength` are taken from SHA-256(`salt` + ":subnet:" + `name`).
Throws if `prefixLength` is not longer than the network's mask or exceeds the address length.

- **Type:** `{ salt : String, network : String, name : String, prefixLength : Int } -> String`
- **Example:** `hashedSubnet { salt = "s"; network = "fd12:3456:789a::/48"; name = "office"; prefixLength = 64; } # "fd12:3456:789a:894d::/64"`

#### Host range

### `broadcast`
Broadcast address of an IPv4 network, without mask. Throws for IPv6. An address without mask is a /32.

- **Type:** `String -> String`
- **Example:** `broadcast "10.0.0.0/23" # "10.0.1.255"`

---

### `firstHost`
First usable host address, without mask. IPv4: network + 1, the network address for /31 (RFC 3021) and /32.
IPv6: network + 1 (skips the subnet-router anycast address), the network address for /127 (RFC 6164) and /128.

- **Type:** `String -> String`
- **Example:** `firstHost "10.0.0.0/24" # "10.0.0.1"`

---

### `lastHost`
Last usable host address, without mask. IPv4: broadcast - 1 (the broadcast address for /31 and /32).
IPv6: all device bits set.

- **Type:** `String -> String`
- **Example:** `lastHost "10.0.0.0/23" # "10.0.1.254"`

---

### `hostCount`
Number of usable host addresses by the rules of `firstHost`/`lastHost`. Throws for IPv6
networks shorter than /65 (the count does not fit into a 64 bit integer).

- **Type:** `String -> Int`
- **Example:** `hostCount "192.168.0.0/24" # 254`

#### Validation helpers for allocations

### `assertUniqueAddresses`
Returns the list unchanged, throws listing the duplicates if two addresses are equal (compared
canonically and ignoring the mask, so `"10.0.0.1/24"` and `"10.0.0.1"` are duplicates).

- **Type:** `[ String ] -> [ String ]`
- **Example:** `assertUniqueAddresses [ "10.0.0.1" "10.0.0.2/24" ] # [ "10.0.0.1" "10.0.0.2/24" ]`

---

### `assertNoOverlap`
Returns the list unchanged, throws listing the overlapping pairs if two networks overlap. All
networks must be of the same family.

- **Type:** `[ String ] -> [ String ]`
- **Example:** `assertNoOverlap [ "10.0.0.0/24" "10.0.1.0/24" ] # [ "10.0.0.0/24" "10.0.1.0/24" ]`

#### Classification
All classification functions ignore the mask of the input and throw on invalid input.
IPv4-mapped IPv6 addresses are classified as IPv6 (e.g. `::ffff:10.0.0.1` is not private).

### `isPrivate`
10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (RFC 1918) or fc00::/7 (RFC 4193).

- **Type:** `String -> Bool`
- **Example:** `isPrivate "172.31.0.1" # true`

---

### `isLoopback`
127.0.0.0/8 or ::1.

- **Type:** `String -> Bool`
- **Example:** `isLoopback "127.1.2.3" # true`

---

### `isLinkLocal`
169.254.0.0/16 or fe80::/10.

- **Type:** `String -> Bool`
- **Example:** `isLinkLocal "fe80::1/64" # true`

---

### `isULA`
IPv6 unique local address, fc00::/7. Always false for IPv4.

- **Type:** `String -> Bool`
- **Example:** `isULA "fd12:3456::1" # true`

---

### `isMulticast`
224.0.0.0/4 or ff00::/8.

- **Type:** `String -> Bool`
- **Example:** `isMulticast "ff02::1" # true`

---

### `ipX.special`
Well-known special-purpose networks of each family as normalized CIDR strings: the most
important entries of the IANA special-purpose address registries (RFC 6890 and updates) plus
multicast. The classification functions above are built on them.

```nix
lib.net.ip6.special.documentation                       # "2001:db8::/32"
lib.net.ip4.special.sharedAddressSpace                  # "100.64.0.0/10"
lib.net.inSubnet "::ffff:192.0.2.1" lib.net.ip6.special.ipv4Mapped # true
```

**IPv4: `ip4.special`**

| Name                      | Network              | Reference                                                          |
| ------------------------- | -------------------- | ------------------------------------------------------------------ |
| `thisNetwork`             | `0.0.0.0/8`          | RFC 791                                                            |
| `private10`               | `10.0.0.0/8`         | RFC 1918                                                           |
| `sharedAddressSpace`      | `100.64.0.0/10`      | RFC 6598, carrier-grade NAT                                        |
| `loopback`                | `127.0.0.0/8`        | RFC 1122                                                           |
| `linkLocal`               | `169.254.0.0/16`     | RFC 3927                                                           |
| `private172`              | `172.16.0.0/12`      | RFC 1918                                                           |
| `ietfProtocolAssignments` | `192.0.0.0/24`       | RFC 6890, contains e.g. DS-Lite, PCP/TURN anycast, NAT64 discovery |
| `documentation1`          | `192.0.2.0/24`       | RFC 5737, TEST-NET-1                                               |
| `private192`              | `192.168.0.0/16`     | RFC 1918                                                           |
| `benchmarking`            | `198.18.0.0/15`      | RFC 2544                                                           |
| `documentation2`          | `198.51.100.0/24`    | RFC 5737, TEST-NET-2                                               |
| `documentation3`          | `203.0.113.0/24`     | RFC 5737, TEST-NET-3                                               |
| `multicast`               | `224.0.0.0/4`        | RFC 5771                                                           |
| `reserved`                | `240.0.0.0/4`        | RFC 1112                                                           |
| `limitedBroadcast`        | `255.255.255.255/32` | RFC 919, lies within `reserved`                                    |

**IPv6: `ip6.special`**

| Name                      | Network             | Reference                                                      |
| ------------------------- | ------------------- | -------------------------------------------------------------- |
| `unspecified`             | `::/128`            | RFC 4291                                                       |
| `loopback`                | `::1/128`           | RFC 4291                                                       |
| `ipv4Mapped`              | `::ffff:0.0.0.0/96` | RFC 4291                                                       |
| `nat64`                   | `64:ff9b::/96`      | RFC 6052, IPv4/IPv6 translation well-known prefix              |
| `nat64Local`              | `64:ff9b:1::/48`    | RFC 8215, local-use IPv4/IPv6 translation                      |
| `discardOnly`             | `100::/64`          | RFC 6666                                                       |
| `ietfProtocolAssignments` | `2001::/23`         | RFC 2928, contains e.g. Teredo, benchmarking, PCP/TURN anycast |
| `documentation`           | `2001:db8::/32`     | RFC 3849                                                       |
| `sixToFour`               | `2002::/16`         | RFC 3056                                                       |
| `documentation2`          | `3fff::/20`         | RFC 9637                                                       |
| `uniqueLocal`             | `fc00::/7`          | RFC 4193                                                       |
| `linkLocal`               | `fe80::/10`         | RFC 4291                                                       |
| `multicast`               | `ff00::/8`          | RFC 4291                                                       |

Blocks that lie within a listed block are left out, e.g. the PCP/TURN anycast and NAT64
discovery addresses inside `192.0.0.0/24`; check against the containing block instead.

#### Formatting

### `canonical'`
Canonical spelling (RFC 5952 for IPv6, IPv4-mapped addresses as `::ffff:a.b.c.d`) of an address. The mask is kept
if and only if the input has one, device bits are kept. Returns `null` if invalid.

- **Type:** `String -> String | null`
- **Example:** `canonical' "2001:DB8:0::1/64" # "2001:db8::1/64"`

---

### `canonical`
Like `canonical'`, but throws on invalid input.

- **Type:** `String -> String`
- **Example:** `canonical "0:0:0:0:0:ffff:c000:201" # "::ffff:192.0.2.1"`

---

### `ipX.expand`
Spells out an address in full: for IPv6 all eight components with four digits and no `::`;
for IPv4 the canonical dotted quad (no zero padding). The mask is kept if the input has one.

- **Type:** `String -> String`
- **Example:** `ip6.expand "2001:db8::1/64" # "2001:0db8:0000:0000:0000:0000:0000:0001/64"`

---

### `toArpa`
Reverse DNS name: the PTR name of an address without mask, or the reverse zone of a network.
Throws if the mask is not a multiple of 8 (IPv4) or 4 (IPv6). See the example above.

- **Type:** `String -> String`
- **Example:** `toArpa "2001:db8::/32" # "8.b.d.0.1.0.0.2.ip6.arpa"`

#### NAT64

### `checkNat64Prefix`
Valid NAT64 prefix: IPv6 network with explicit mask of 32, 40, 48, 56, 64 or 96, no device bits, bits 64–71 zero (RFC 6052 2.2).

- **Type:** `Any -> Bool`
- **Example:** `checkNat64Prefix "64:ff9b::/96" # true`

---

### `nat64Address'` / `nat64Address`
Embeds an IPv4 address under a NAT64 prefix (default `64:ff9b::/96`) per RFC 6052 2.2. The primed
variant returns `null` on invalid input, the other throws, also when the well-known prefix is used
with a non-global IPv4 address (RFC 6052 3.1).

- **Type:** `{ prefix ? String, address : String } -> String`
- **Example:** `nat64Address { prefix = "2001:db8:100::/40"; address = "192.0.2.33"; } # "2001:db8:1c0:2:21::"`

---

### `nat64Extract'` / `nat64Extract`
Extracts the embedded IPv4 address, the inverse of `nat64Address`. `null` / throws if the address
is not within the prefix.

- **Type:** `{ prefix ? String, address : String } -> String`
- **Example:** `nat64Extract { address = "64:ff9b::c000:221"; } # "192.0.2.33"`

#### EUI-64

### `eui64FromMac`
SLAAC address of an IPv6 /64 from a MAC address using the modified EUI-64 interface identifier
(RFC 4291). Throws if the network is not an IPv6 /64 or the MAC is invalid.

- **Type:** `{ network : String, mac : String } -> String`
- **Example:** `eui64FromMac { network = "2001:db8::/64"; mac = "52:54:00:12:34:56"; } # "2001:db8::5054:ff:fe12:3456"`

#### Endpoints, MAC addresses and netmasks

### `decomposeEndpoint'`
Splits an endpoint (`"1.2.3.4:53"` or `"[2001:db8::1]:53"`, no mask, port 0 to 65535) into
`{ address; port; family; }` with the address in canonical spelling. Returns `null` if invalid.

- **Type:** `String -> { address : String, port : Int, family : String } | null`
- **Example:** `decomposeEndpoint' "[2001:DB8:0::1]:443" # { address = "2001:db8::1"; family = "ip6"; port = 443; }`

---

### `decomposeEndpoint`
Like `decomposeEndpoint'`, but throws on invalid input.

- **Type:** `String -> { address : String, port : Int, family : String }`
- **Example:** `(decomposeEndpoint "1.2.3.4:53").port # 53`

---

### `checkMac`
Checks for a MAC address: six hex byte pairs consistently separated by `:` or `-`.

- **Type:** `String -> Bool`
- **Example:** `checkMac "00:1A:2b:3c:4d:5e" # true`

---

### `macToParts'`, `macToParts`
Splits a MAC address into its six bytes (`null` / throws if invalid).

- **Type:** `String -> [ Int ]`
- **Example:** `macToParts "00:1a:2b:3c:4d:5e" # [ 0 26 43 60 77 94 ]`

---

### `prefixFromNetmask'`, `prefixFromNetmask`
Prefix length of a contiguous IPv4 or IPv6 netmask without `/mask` (`null` / throws if invalid).

- **Type:** `String -> Int`
- **Example:** `prefixFromNetmask "255.255.255.0" # 24`

---

### `ipX.netmaskFromPrefix`
Netmask for a prefix length. Throws if out of range.

- **Type:** `Int -> String`
- **Example:** `ip6.netmaskFromPrefix 32 # "ffff:ffff::"`

#### Sorting

### `compareAddresses`
Compares two addresses: IPv4 before IPv6, then by value, then by mask (shorter first, no mask = full mask).

- **Type:** `String -> String -> Int`
- **Example:** `compareAddresses "10.0.0.2" "10.0.0.10" # -1`

---

### `sortAddresses`
Sorts addresses by `compareAddresses`, keeping their spelling. Throws on invalid input.

- **Type:** `[ String ] -> [ String ]`
- **Example:** `sortAddresses [ "::1" "10.0.0.10" "10.0.0.2" ] # [ "10.0.0.2" "10.0.0.10" "::1" ]`

#### Low-level

### `pow`
Computes the power of an integer raised to a non-negative integer exponent.

- **Type:** `Int -> Int -> Int`
- **Example:** `pow 2 3 # 8`

---

### `partsBitAnd`
Bitwise AND of two lists of integers representing IP address parts.

- **Type:** `[ Int ] -> [ Int ] -> [ Int ]`
- **Example:** `partsBitAnd [255 0 0 0] [255 255 255 0] # [255 0 0 0]`

---

### `ipX.composeStr`
Builds an address string from its parts and a mask (`null` for no mask).

- **Type:** `[ Int ] -> Int | null -> String`
- **Example:** `ip4.composeStr [10 0 0 1] 8 # "10.0.0.1/8"`

---

### `ipX.calculateNetworkMaskParts`
Computes the network mask for a given CIDR mask.

- **Type:** `Int -> [ Int ]`
- **Example:** `ip4.calculateNetworkMaskParts 20 # [255 255 240 0]`

---

### `ipX.calculateDeviceMaskParts`
Computes the device mask for a given CIDR mask.

- **Type:** `Int -> [ Int ]`
- **Example:** `ip4.calculateDeviceMaskParts 24 # [0 0 0 255]`

---

### `hexBits`, `setBitsFromHex`
Helpers of `hashedAddress`/`hashedSubnet`: read bits from a hex string, and replace a bit range of
an address' parts with bits from a hex string.

- **Type:** `String -> Int -> Int -> Int`, `{ meta, parts : [ Int ], from : Int, to : Int, hex : String } -> [ Int ]`
- **Example:** `hexBits "f0" 0 4 # 15`

---

### `ipX.meta`
Constants of the address family (`name`, `bitWidth`, `components`, `componentBitWidth`, ...).
`ipN` builds such an interface from a `meta` set.

## Development
Tests are plain Nix expressions:

```sh
nix flake check   # evaluates all tests (fails if any test fails)
nix eval .#tests  # number of test cases, or an error listing every failing case
```

- [tests.nix](tests.nix): the test runner, documents the test case format.
- [tests/core.nix](tests/core.nix): parsing, composing, decomposing, subnet relations, address allocation, hashing and the library overlay.
- [tests/types.nix](tests/types.nix): option types, endpoints, MAC addresses and netmasks.
- [tests/api.nix](tests/api.nix): `inSubnet`, host range, overlap/uniqueness assertions, classification, `expand`, `toArpa`, EUI-64 and sorting.

CI ([.github/workflows/check.yml](.github/workflows/check.yml)) runs `nix flake check` on every push and pull request.

## Contributing
Issues and pull requests are welcome.
