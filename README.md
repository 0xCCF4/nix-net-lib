# Nix network library
A nix library for parsing, validating and manipulating IPv4 and IPv6 addresses.

## Features
- **Parse** IPv4 and IPv6 addresses in CIDR notation (e.g., `192.168.1.1/24`, `2001:db8::1/64`)
- **Decompose** addresses into network, device, mask, and integer components
- **Compose** string addresses from integer parts and mask values
- **Validate** IPv4/6 addresses
- **Type support** for NixOS modules and options
- **IPv6 compression support** use of compression operator `::` supported 

## Usage

Import the library in your Nix flake:

```nix
inputs = {
    nix-net-lib.url = "github:0xCCF4/nix-net-lib";
};
```

and optionally add its overlay to your NixOS config:

```nix
nixpkgs.overlays = [ nix-net-lib.overlays.default ];
```

## Example: Decomposing an IPv6 Address

```nix
lib.net.ip4.decompose "fe80::11/64"
# Returns:
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
        type = lib.types.net.ip4; # accept any valid IPv4/IPv6
        description = "Server ip address";
    };
};
```

## Example: Calculating a network address from index
```nix
lib.net.assignAddress "10.0.0.0/16" 300
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

## API Reference
See [lib.nix](lib.nix) for the full documentation.

### NixOS Option Types
When using the overlay, types are added into `lib.types.net.XXX`, otherwise types are available via `nix-net-lib.lib.types.XXXX`.

| Type Alias                | Description                                                                                     |
|---------------------------|-------------------------------------------------------------------------------------------------|
| `ip`                      | Any valid IPv4 or IPv6 address                                                                  |
| `ipNetwork`               | Normalized IPv4 or IPv6 network address (address + mask, no device part)                        |
| `ipNoMask`                | IPv4 or IPv6 address, without trailing mask                                                     |
| `ipExplicitMask`          | IPv4 or IPv6 address, with explicit mask set                                                    |
| `ip4`                     | Any valid IPv4 address                                                                          |
| `ip6`                     | Any valid IPv6 address                                                                          |
| `ip4Network`              | Normalized IPv4 network address (address + mask, no device part)                                |
| `ip6Network`              | Normalized IPv6 network address (address + mask, no device part)                                |
| `ip4NoMask`               | IPv4 address, without trailing mask                                                             |
| `ip6NoMask`               | IPv6 address, without trailing mask                                                             |
| `ip4ExplicitMask`         | IPv4 address, with explicit mask set                                                            |
| `ip6ExplicitMask`         | IPv6 address, with explicit mask set                                                            |
| `ip4WithinNetworkStrict <ipAddress>`  | IPv4 address within a given subnet, mask must match exactly                         |
| `ip6WithinNetworkStrict <ipAddress>`  | IPv6 address within a given subnet, mask must match exactly                         |
| `ip4WithinNetwork`        | IPv4 address within a given subnet, address may have a larger mask value than the subnet        |
| `ip6WithinNetwork`        | IPv6 address within a given subnet, address may have a larger mask value than the subnet        |

### Function reference
When using the overlay, function are added into `lib.net.XXX`, otherwise functions are available via `nix-net-lib.lib.XXXX`.

### `pow`
Computes the power of a number raised to a positive integer exponent.

- **Type:** `Int -> Int -> Number`
- **Example:** `pow 2 3 # 8`

---

### `partsBitAnd`
Bitwise AND of two lists of integers representing IP address parts.

- **Type:** `[ Int ] -> [ Int ] -> [ Int ]`
- **Example:** `partsBitAnd [255 0 0 0] [255 255 255 0] # [255 0 0 0]`

---

### `subnetRelation'`
Returns the network relation between two IP addresses as `"superset"`, `"equal"`, `"subset"`, `"disjoint"`, or `null` if invalid.

- **Type:** `String -> String -> String`
- **Example:** `subnetRelation' "1.2.3.4/24" "1.2.0.0/16" # "subset"`

---

### `subnetRelation`
Like `subnetRelation'`, but throws on invalid input.

- **Type:** `String -> String -> String`
- **Example:** `subnetRelation "1.2.3.4/16" "1.2.0.0/16" # "equal"`

---

### `laysWithinSubnet'`
Checks if an IP address is within a subnet (mask may be larger).

- **Type:** `String -> String -> Bool`
- **Example:** `laysWithinSubnet' "1.2.3.4/24" "1.2.0.0/16" # true`

---

### `laysWithinSubnet`
Like `laysWithinSubnet'`, but throws on invalid input.

- **Type:** `String -> String -> Bool`
- **Example:** `laysWithinSubnet "1.2.3.4/24" "1.2.0.0/16" # true`

---

### ``assignAddress'
Calculates the n-th address in the given subnet.

- **Type:** `String -> Int -> String | null`
- **Example:** `assignAddress' "10.10.0.0/16" 500`

---

### ``assignAddress
Like `assignAddress'`, but throws on invalid input or if the index is too large for the subnet.

- **Type:** `String -> Int -> String`
- **Example:** `assignAddress' "10.10.0.0/16" 500`


---

### `hashedAddress`
Derives a stable address for a device from its name inside an IPv4 or IPv6 network: all device
bits are taken from SHA-256(`salt` + ":address:" + `name`). The result may collide with other
names or be an address with a special meaning (e.g. the network address) in small networks.

- **Type:** `{ salt : String, network : String, name : String } -> String`
- **Example:** `hashedAddress { salt = "s"; network = "2001:db8::/64"; name = "host-a"; } # "2001:db8::f0a3:42e6:b7cf:1582"`

---

### `hashedSubnet`
Derives a stable subnet for a name out of a larger IPv4 or IPv6 network: the bits between the
network's mask and `prefixLength` are taken from SHA-256(`salt` + ":subnet:" + `name`).

- **Type:** `{ salt : String, network : String, name : String, prefixLength : Int } -> String`
- **Example:** `hashedSubnet { salt = "s"; network = "fd12:3456:789a::/48"; name = "office"; prefixLength = 64; } # "fd12:3456:789a:894d::/64"`

---

### `calculateDeviceMaskParts`
Computes the device mask for a given CIDR mask.

- **Type:** `Int -> [ Int ]`
- **Example:** `calculateDeviceMaskParts 24 # [0 0 0 255]`

---

### `decompose'`
Decomposes a CIDR address string into its components. Returns `null` if invalid.

- **Type:** `String -> { ... } | null`
- **Example:** `decompose' "192.168.1.1/24"`
- **Return value**:
    - `addressParts`: List of integers for the full IP address.
    - `address`: Normalized IP address in CIDR notation.
    - `addressNoMask`: IP address without mask.
    - `networkParts`: Integers for the network part.
    - `network`: Network part as string.
    - `networkNoMask`: Network part without mask.
    - `deviceParts`: Integers for the device part.
    - `device`: Device part as string.
    - `deviceNoMask`: Device part without mask.
    - `networkMaskParts`: Network mask parts.
    - `networkMask`: Network mask as string.
    - `networkMaskNoMask`: Network mask without mask notation.
    - `mask`: CIDR mask as integer.

---

### `decompose`
Like `decompose'`, but throws on invalid input.

- **Type:** `String -> { ... }`
- **Example:** `decompose "192.168.1.1/24"`

---

### `ipX.checkIpParts`
Checks if a list of integers is a valid IP address.

- **Type:** `[ Int ] -> Bool`
- **Example:** `checkIpParts [192 168 1 1] # true`

---

### `ipX.checkIpMask`
Checks if an integer is a valid CIDR mask.

- **Type:** `Int -> Bool`
- **Example:** `checkIpMask 24 # true`

---

### `ipX.checkNormalizedNetwork`
Checks if a string is a normalized network address.

- **Type:** `String -> Bool`
- **Example:** `checkNormalizedNetwork "192.168.1.6/24" # false, since .6`

---

### `ipX.check`
Checks if a string is a valid IP address in CIDR notation.
Accepts IPv4 dotted quads without leading zeros, all IPv6 text forms of RFC 4291 2.2 (including an embedded IPv4 address like `::ffff:192.0.2.1`), and masks of 0 to 32 (IPv4) or 0 to 128 (IPv6). Zone IDs (`fe80::1%eth0`) are rejected.

- **Type:** `String -> Bool`
- **Example:** `check "192.168.1.1/24" # true`

---

### `ipX.checkNoMask`
Checks if a string is a valid IP address without a mask.

- **Type:** `String -> Bool`
- **Example:** `checkNoMask "192.168.1.1" # true`

---

### `ipX.checkWithMask`
Checks if a string is a valid IP address with an explicit mask.

- **Type:** `String -> Bool`
- **Example:** `checkWithMask "192.168.1.1/24" # true`


## Contributing
Issues and pull requests are welcome.
