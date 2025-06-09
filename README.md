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

## API Reference
See [lib.nix](lib.nix) for the full documentation.

### NixOS Option Types
When using the overlay, types are added into `lib.types.net.XXX`, otherwise types are available via `nix-net-lib.lib.types.XXXX`.

| Type Alias         | Description                                                        |
|--------------------|--------------------------------------------------------------------|
| `ip`               | IPv4 or IPv6 address                                               |
| `ipNetwork`        | IPv4 or IPv6 network (address + mask), no device part              |
| `ipNoMask`         | IPv4 or IPv6 address (no mask)                                     |
| `ipExplicitMask`   | IPv4 or IPv6 address with an explicit mask                         |
| `ip4`              | IPv4 address                                                       |
| `ip4Network`       | IPv4 network (address + mask), no device part                      |
| `ip4NoMask`        | IPv4 address (no mask)                                             |
| `ip4ExplicitMask`  | IPv4 address with an explicit mask                                 |
| `ip6`              | IPv6 address                                                       |
| `ip6Network`       | IPv6 network (address + mask), no device part                      |
| `ip6NoMask`        | IPv6 address (no mask)                                             |
| `ip6ExplicitMask`  | IPv6 address with an explicit mask                                 |

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

### `ip`
A function that takes an IP address and returns the appropriate interface
of functions to process it.

- **Type:** `String -> {...}`
- **Example:** ip "1.2.3.4"

The resulting set is documented below. If provided an ip4 address, then the set `ip4`
is returned, otherwise if an ip6 address is provided the set `ip6`, else an error is
thrown.

---

### `ip4`/`ip6` (IP Address Utilities)

### `composeStr`
Converts a list of address parts and a mask to a CIDR string.

- **Type:** `[ Int ] -> Int | null -> String`
- **Example:** `composeStr [192 168 1 1] 24 # "192.168.1.1/24"`

---

### `calculateNetworkMaskParts`
Computes the network mask for a given CIDR mask.

- **Type:** `Int -> [ Int ]`
- **Example:** `calculateNetworkMaskParts 24 # [255 255 255 0]`

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
    - `mask`: CIDR mask as integer.

---

### `decompose`
Like `decompose'`, but throws on invalid input.

- **Type:** `String -> { ... }`
- **Example:** `decompose "192.168.1.1/24"`

---

### `checkIpParts`
Checks if a list of integers is a valid IP address.

- **Type:** `[ Int ] -> Bool`
- **Example:** `checkIpParts [192 168 1 1] # true`

---

### `checkIpMask`
Checks if an integer is a valid CIDR mask.

- **Type:** `Int -> Bool`
- **Example:** `checkIpMask 24 # true`

---

### `checkNormalizedNetwork`
Checks if a string is a normalized network address.

- **Type:** `String -> Bool`
- **Example:** `checkNormalizedNetwork "192.168.1.6/24" # false, since .6`

---

### `check`
Checks if a string is a valid IP address in CIDR notation.

- **Type:** `String -> Bool`
- **Example:** `check "192.168.1.1/24" # true`

---

### `checkNoMask`
Checks if a string is a valid IP address without a mask.

- **Type:** `String -> Bool`
- **Example:** `checkNoMask "192.168.1.1" # true`

---

### `checkWithMask`
Checks if a string is a valid IP address with an explicit mask.

- **Type:** `String -> Bool`
- **Example:** `checkWithMask "192.168.1.1/24" # true`


## Contributing
Issues and pull requests are welcome.
