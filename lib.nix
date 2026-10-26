{
  nixpkgs ? null,
  lib ? nixpkgs.lib,
  ...
}@inputs:
with builtins;
with lib;
let
  rep2Add = mask: val: if mask == 0 then 0 else 2 * (rep2Add (mask - 1) val) + val;

  # Decimal number of at most three digits, without leading zeros. Used for IPv4 octets
  # (RFC 6943 3.1.1: leading zeros are ambiguous, they may be read as octal) and masks.
  # The length limit also keeps `toInt` from overflowing or throwing.
  checkDecimal = val: typeOf val == "string" && match "0|[1-9][0-9]{0,2}" val != null;
  # RFC 4291 2.2.1: an IPv6 component has one to four hexadecimal digits
  checkHex = val: match "[0-9a-fA-F]{1,4}" val != null;

  # Splits an address with at most one "::" into its components, or returns null.
  # "::" stands for one or more zero components (RFC 4291 2.2.2). Empty components
  # outside of "::" (e.g. ":1:2:3:4:5:6:7" or "1:::2") are rejected, as is a wrong number
  # of components. Never throws.
  ipGapSplit =
    meta: str:
    let
      pieces = splitString "${meta.componentSeparator}${meta.componentSeparator}" str;
      splitPiece = piece: if piece == "" then [ ] else splitString meta.componentSeparator piece;

      lstBeforeGap = splitPiece (head pieces);
      lstAfterGap = splitPiece (last pieces);
      fillerLength = meta.components - length lstBeforeGap - length lstAfterGap;

      noGap = splitString meta.componentSeparator str;
    in
    if length pieces == 1 then
      (if any (part: part == "") noGap || length noGap != meta.components then null else noGap)
    else if
      length pieces > 2 || any (part: part == "") (lstBeforeGap ++ lstAfterGap) || fillerLength < 1
    then
      null
    else
      lstBeforeGap ++ genList (i: "0") fillerLength ++ lstAfterGap;

  # Replaces a trailing dotted-quad IPv4 address in an IPv6 address by two hexadecimal
  # components (RFC 4291 2.2.3, e.g. "::ffff:192.0.2.1" -> "::ffff:c000:201"),
  # returns null if the IPv4 part is invalid.
  ip6EmbeddedIp4 =
    ip4: str:
    let
      parts = splitString ":" str;
      ip4Part = last parts;
      ip4Decomposed = ip4.decompose' ip4Part;
      ip4Parts = ip4Decomposed.addressParts;
      hex = a: b: toLower (trivial.toHexString (a * 256 + b));
    in
    if !(hasInfix "." ip4Part) then
      str
    else if length parts < 2 || ip4Decomposed == null then
      null
    else
      concatStringsSep ":" (
        init parts
        ++ [
          (hex (elemAt ip4Parts 0) (elemAt ip4Parts 1))
          (hex (elemAt ip4Parts 2) (elemAt ip4Parts 3))
        ]
      );

  # Renders IPv6 components per RFC 5952: lower case, longest run of (at least two) zero
  # components replaced by "::" and IPv4-mapped addresses as "::ffff:a.b.c.d" (RFC 5952 5).
  ipGapJoin =
    meta: parts:
    let
      ip4Mapped =
        take 6 parts == [
          0
          0
          0
          0
          0
          65535
        ];
      ip4MappedStr = "::ffff:${toString (elemAt parts 6 / 256)}.${toString (mod (elemAt parts 6) 256)}.${
        toString (elemAt parts 7 / 256)
      }.${toString (mod (elemAt parts 7) 256)}";

      findGaps =
        foldl
          (
            acc: part:
            let
              currentGapOrNull = filter (x: x.end == part.index - 1) acc;
              currentGap =
                if length currentGapOrNull > 0 then
                  head currentGapOrNull // { end = part.index; }
                else
                  {
                    start = part.index;
                    end = part.index;
                  };
            in
            if part.value == 0 then (filter (gap: gap.start != currentGap.start) acc) ++ [ currentGap ] else acc
          )
          [ ]
          (
            map (x: {
              value = x.fst;
              index = x.snd;
            }) (lists.zipLists parts (genList (i: i) meta.components))
          );

      # RFC 5952 4.2.2: "::" must not shorten a single zero component
      compressibleGaps = filter (gap: gap.end > gap.start) findGaps;

      longestGap =
        if length compressibleGaps == 0 then
          null
        else
          foldl (
            acc: gap: if gap.end - gap.start > acc.end - acc.start then gap else acc
          ) (head compressibleGaps) compressibleGaps;

      strParts = map meta.componentToString parts;

      lstBeforeGap = if longestGap.start == 0 then [ "" ] else lists.sublist 0 longestGap.start strParts;

      lstAfterGap =
        if longestGap.end == meta.components - 1 then
          [ "" ]
        else
          lists.sublist (longestGap.end + 1) meta.components strParts;

      strPartsRemovedGap = if longestGap == null then strParts else lstBeforeGap ++ [ "" ] ++ lstAfterGap;
    in
    if ip4Mapped then ip4MappedStr else concatStringsSep ":" strPartsRemovedGap;

  # Adds `delta` (+1 or -1) to an address given as list of components, carrying across
  # components. Wraps around at the ends of the address space (callers avoid that).
  partsStep =
    meta: delta: parts:
    (foldr
      (
        part: acc:
        let
          value = part + acc.carry;
        in
        if value > meta.componentMask then
          {
            carry = 1;
            result = [ 0 ] ++ acc.result;
          }
        else if value < 0 then
          {
            carry = -1;
            result = [ meta.componentMask ] ++ acc.result;
          }
        else
          {
            carry = 0;
            result = [ value ] ++ acc.result;
          }
      )
      {
        carry = delta;
        result = [ ];
      }
      parts
    ).result;

  # Host range of a decomposed network: broadcast (all device bits set), first and last
  # usable address as component lists. IPv4: RFC 3021 for /31, a /32 is its only address,
  # otherwise network and broadcast address are excluded. IPv6: the subnet-router anycast
  # address (all device bits zero) is excluded, RFC 6164 for /127, a /128 is its only address.
  hostRange =
    decomposed:
    let
      meta = decomposed._meta;
      deviceBits = meta.bitWidth - decomposed.mask;
      network = decomposed.networkParts;
      broadcast = zipListsWith (
        part: maskPart: bitOr part (bitXor maskPart meta.componentMask)
      ) network decomposed.networkMaskParts;
      isIp4 = meta.name == "ip4";
    in
    {
      inherit meta deviceBits broadcast;
      first = if deviceBits <= 1 then network else partsStep meta 1 network;
      last = if deviceBits <= 1 || !isIp4 then broadcast else partsStep meta (-1) broadcast;
    };

  # True if `address` lies within one of the networks `ranges.ip4` or `ranges.ip6` (by the
  # family of `address`), ignoring the mask of `address`. Throws if `address` is invalid.
  classifyAddress =
    decompose: ranges: address:
    let
      decomposed = decompose address;
    in
    any (
      range:
      let
        network = decompose range;
      in
      zipListsWith bitAnd decomposed.addressParts network.networkMaskParts == network.networkParts
    ) ranges.${decomposed._meta.name};

  # Ranges for `isGlobal` per the "Globally Reachable" column of the IANA special-purpose
  # address registries. An address is global if it lies within `space` but not within
  # `nonGlobal`, or within `exceptions` (globally reachable blocks inside non-global ones).
  # Multicast is handled separately below.
  globalRanges = with self; {
    space = {
      ip4 = [ "0.0.0.0/0" ];
      ip6 = with ip6.special; [
        globalUnicast
        nat64
      ];
    };
    nonGlobal = {
      ip4 = with ip4.special; [
        thisNetwork
        private10
        sharedAddressSpace
        loopback
        linkLocal
        private172
        ietfProtocolAssignments
        documentation1
        private192
        benchmarking
        documentation2
        documentation3
        reserved
      ];
      ip6 = with ip6.special; [
        ietfProtocolAssignments
        documentation
        sixToFour
        documentation2
      ];
    };
    exceptions = {
      ip4 = with ip4.special; [
        pcpAnycast
        turnAnycast
      ];
      ip6 = with ip6.special; [
        pcpAnycast
        turnAnycast
        dnsSdSrpAnycast
        amt
        as112
        orchidV2
        droneRemoteId
      ];
    };
  };

  # IPv6 multicast scope names (RFC 4291 2.7, RFC 7346 2) by the value of the scope field
  ip6MulticastScopes = [
    "reserved" # 0
    "interface" # 1
    "link" # 2
    "realm" # 3
    "admin" # 4
    "site" # 5
    "unassigned" # 6
    "unassigned" # 7
    "organization" # 8
    "unassigned" # 9
    "unassigned" # a
    "unassigned" # b
    "unassigned" # c
    "unassigned" # d
    "global" # e
    "reserved" # f
  ];

  # Hex digits of an address given as list of components, e.g. [ 192 0 2 1 ] -> "c0000201"
  partsToHex =
    meta: parts:
    concatMapStrings (
      part: fixedWidthString (meta.componentBitWidth / 4) "0" (strings.toLower (trivial.toHexString part))
    ) parts;

  # A mapping between IPv4 and IPv6 addresses, as used by NAT64 (RFC 6052): `ip4` and
  # `ip6` are the decomposed prefixes,
  # each segment maps `length` bits at offset `ip4` of the IPv4 address to offset `ip6`
  # of the IPv6 address.

  # RFC 6052 2.2: the IPv4 address follows the prefix, skipping bits 64 to 71 (the u octet)
  nat64Mapping =
    prefix:
    let
      p = self.ip6.decompose prefix;
      before = min 32 (64 - p.mask); # IPv4 bits placed before the u octet
    in
    {
      ip6 = p;
      ip4 = self.ip4.decompose "0.0.0.0/0";
      segments =
        if p.mask == 96 then
          [
            {
              ip4 = 0;
              ip6 = 96;
              length = 32;
            }
          ]
        else
          filter (segment: segment.length > 0) [
            {
              ip4 = 0;
              ip6 = p.mask;
              length = before;
            }
            {
              ip4 = before;
              ip6 = 72;
              length = 32 - before;
            }
          ];
    };

  # Translates the decomposed `address` from side `fromSide` ("ip4" or "ip6") of `mapping`
  # to side `toSide`: the segments of the address are copied into the network address of
  # the `toSide` prefix. Returns the address without mask.
  mapAddress =
    {
      mapping,
      fromSide,
      toSide,
      address,
    }:
    let
      target = mapping.${toSide};
    in
    target._meta.partsToStr (
      foldl (
        parts: segment:
        self.setBitsFromHex {
          meta = target._meta;
          inherit parts;
          from = segment.${toSide};
          to = segment.${toSide} + segment.length;
          hex = partsToHex address._meta address.addressParts;
          offset = segment.${fromSide};
        }
      ) target.networkParts mapping.segments
    );

  # Implementation of nat64Address: { value; error; } with `error` null on success
  nat64Embed =
    {
      prefix ? self.ip6.special.nat64,
      address,
    }:
    let
      inherit (self) ip4 ip6;
      v4 = ip4.decompose' address;
      nonGlobal = any (network: self.inSubnet' v4.addressNoMask network) (
        with ip4.special;
        [
          thisNetwork
          private10
          private172
          private192
          sharedAddressSpace
          loopback
          linkLocal
        ]
      );
    in
    if v4 == null then
      {
        value = null;
        error = "invalid IPv4 address ${toJSON address}";
      }
    else if !self.checkNat64Prefix prefix then
      {
        value = null;
        error = "invalid NAT64 prefix ${toJSON prefix}, must be an IPv6 network of length 32, 40, 48, 56, 64 or 96 with bits 64 to 71 zero (RFC 6052 2.2)";
      }
    else if (ip6.decompose prefix).network == ip6.special.nat64 && nonGlobal then
      {
        value = null;
        error = "the well-known prefix ${ip6.special.nat64} must not be used with the non-global IPv4 address ${toJSON address} (RFC 6052 3.1), use a network-specific prefix like ${ip6.special.nat64Local}";
      }
    else
      {
        value = mapAddress {
          mapping = nat64Mapping prefix;
          fromSide = "ip4";
          toSide = "ip6";
          address = v4;
        };
        error = null;
      };

  # The public library, bound to a name so that the helpers above can use it
  self = rec {
    /**
      Computes the power of a number raised to a positive integer exponent.
      If the exponent is negative, an error is thrown.

      # Inputs
      `val` : The base number (should be a number).
      `exp` : The exponent (should be an positive integer).

      # Output
      The result of `val` raised to the power of `exp`.

      # Type
      ```nix
      Int -> Int -> Int
      ```
    */
    pow =
      val: exp:
      if typeOf val != "int" || typeOf exp != "int" then
        throw "pow expects integers, got ${toString val}^${toString exp}"
      else if exp < 0 then
        throw "pow does not support negative exponents, got ${toString exp}"
      else if exp == 0 then
        1
      else if exp == 1 then
        val
      else
        val * pow val (exp - 1);

    /**
       Computes the network relation of two ip addresses.

      # Inputs
      `address` : An IP address
      `network` : An IP address

      # Output
      A string representing the relation of the two addresses:
      - "superset"
      - "equal"
      - "subset"
      - "disjoint"
      - `null` if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

      The output must be read as follows: `address` is <output> to/of `network`.

      # Type
      ```nix
      String -> String -> String | null
      ```
    */
    subnetRelation' =
      address: network:
      let
        decomposedAddress = decompose' address;
        decomposedNetwork = decompose' network;

        validAddresses =
          decomposedNetwork != null
          && decomposedAddress != null
          && decomposedNetwork._meta.name == decomposedAddress._meta.name;

        smallestMask = min decomposedAddress.mask decomposedNetwork.mask;

        networkMask = (ip address).calculateNetworkMaskParts smallestMask;

        valueNet = partsBitAnd decomposedAddress.networkParts networkMask;
        networkNet = partsBitAnd decomposedNetwork.networkParts networkMask;
        networkEqual = valueNet == networkNet;
      in
      if !validAddresses then
        null
      else if networkEqual && decomposedAddress.mask < decomposedNetwork.mask then
        "superset"
      else if networkEqual && decomposedAddress.mask == decomposedNetwork.mask then
        "equal"
      else if networkEqual && decomposedAddress.mask > decomposedNetwork.mask then
        "subset"
      else
        "disjoint";

    /**
        Computes the network relation of two ip addresses.
        Same as `subnetRelation'`, but throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

        # Inputs
        `address` : An IP address
        `network` : An IP address

        # Output
        A string representing the relation of the two addresses:
        - "superset"
        - "equal"
        - "subset"
        - "disjoint"

        The output must be read as follows: `address` is <output> to/of `network`.

        # Errors
        Throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).
    */
    subnetRelation =
      address: network:
      let
        result = subnetRelation' address network;
      in
      if result != null then
        result
      else
        throw "Invalid IP addresses: ${toJSON address} and ${toJSON network}";

    /**
      Deprecated alias of `inSubnet'`, kept for compatibility.

      # Type
      ```nix
      String -> String -> Bool
      ```
    */
    laysWithinSubnet' = inSubnet';

    /**
      Deprecated alias of `inSubnet`, kept for compatibility.

      # Errors
      Throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

      # Type
      ```nix
      String -> String -> Bool
      ```
    */
    laysWithinSubnet = inSubnet;

    /**
        Computes the bitwise AND of two lists of integers representing IP address parts.

        # Input
        `addressParts` : A list of integers representing the IP address in its components, e.g. [1, 2, 3, 4]
        `maskParts` : A list of integers representing the mask for the IP address.

        # Output
        A list of integers representing the result of the bitwise AND operation on each corresponding component.

        # Type
        ```nix
        [ Int ] -> [ Int ] -> [ Int ]
        ```
    */
    partsBitAnd =
      addressParts: maskParts:
      if length addressParts != length maskParts then
        throw "partsBitAnd expects lists of equal length, got ${toString (length addressParts)} and ${toString (length maskParts)}"
      else
        map (x: bitAnd x.fst x.snd) (lists.zipLists addressParts maskParts);

    /**
      Decomposes the given IP address using the appropriate IP interface.

      This function attempts to determine the type of the provided `address`
      by using the `ip'` function. If a valid IP interface is found, it calls
      the `decompose'` method of that interface to break down the address into
      its components. If the address type is not recognized, it returns `null`.

      # Input
      `address` : An IP address, which can be either an IPv4 or IPv6 address.

      # Output
      An attribute set containing the decomposed components of the IP address, or `null` if the address is invalid.
      See `ipN.decompose'` for the structure of the output.

      # Type
      ```nix
      String -> { ... } | null
      ```
    */
    decompose' =
      address:
      let
        ipInterface = ip' address;
      in
      if ipInterface != null then ipInterface.decompose' address else null;

    /**
      Decomposes the given IP address using the appropriate IP interface.
      This function attempts to determine the type of the provided `address`
      by using the `ip` function. If a valid IP interface is found, it calls
      the `decompose` method of that interface to break down the address into
      its components. If the address type is not recognized, it throws an error.

      # Input
      `address` : An IP address, which can be either an IPv4 or IPv6 address.

      # Output
      An attribute set containing the decomposed components of the IP address.
      See `ipN.decompose` for the structure of the output.

      # Errors
      Throws an error if the input is not a valid IP address.

      # Type
      ```nix
      String -> { ... }
      ```
    */
    decompose =
      address:
      let
        result = decompose' address;
      in
      if result != null then result else throw "Invalid IP address: ${toJSON address}";

    /**
      Returns the canonical (RFC 5952 for IPv6) spelling of an IPv4 or IPv6 address. The
      trailing /mask is kept if and only if the input has one. The device part is kept, i.e.
      the address is not reduced to its network.

      # Input
      `address` : An IP address, e.g. "2001:DB8:0::1/64".

      # Output
      The canonical spelling, e.g. "2001:db8::1/64", or `null` if the input is invalid.

      # Type
      ```nix
      String -> String | null
      ```
    */
    canonical' =
      address:
      let
        decomposed = decompose' address;
      in
      if decomposed == null then
        null
      else if hasInfix "/" address then
        decomposed.address
      else
        decomposed.addressNoMask;

    /**
      Returns the canonical (RFC 5952 for IPv6) spelling of an IPv4 or IPv6 address.
      Same as `canonical'`, but throws an error if the input is invalid.

      # Input
      `address` : An IP address, e.g. "2001:DB8:0::1/64".

      # Output
      The canonical spelling, e.g. "2001:db8::1/64".

      # Errors
      Throws an error if the input is not a valid IP address.

      # Type
      ```nix
      String -> String
      ```
    */
    canonical =
      address:
      let
        result = canonical' address;
      in
      if result != null then result else throw "Invalid IP address: ${toJSON address}";

    /**
      A function that calculates the n-th address in the given network.

      # Inputs
      `network` : An IP address representing a network in CIDR notation.
      `index` : An integer representing the index of the desired address within the network.

      # Output
      A string representing the n-th address in the given network, without trailing /mask
      (like `hashedAddress`), or `null` if the input is invalid or the index is out of range.

      # Example
      ```nix
      assignAddress' "fe80::/64" 2
      # "fe80::2"
      ```

      # Type
      ```nix
      String -> Int -> String | null
      ```
    */
    assignAddress' =
      network: index:
      let
        ipInterface = ip' network;
        decomposed = ipInterface.decompose' network;
        networkParts = decomposed.networkParts;
        mask = decomposed.mask;

        addressParts = imap0 (
          i: part:
          let
            reversedI = ipInterface.meta.components - 1 - i;
            availableBits =
              ipInterface.meta.componentBitWidth
              - (min ipInterface.meta.componentBitWidth (max 0 (mask - i * ipInterface.meta.componentBitWidth)));

            indexShiftAmount = reversedI * ipInterface.meta.componentBitWidth;
            offset = index / (pow 2 indexShiftAmount);

            data =
              if indexShiftAmount >= 64 then
                {
                  offset = 0;
                  bits = 0;
                }
              else
                {
                  offset = mod offset (ipInterface.meta.componentMask + 1);
                  bits = availableBits;
                };
          in
          if data.offset >= pow 2 availableBits then null else bitOr part data.offset
        ) networkParts;

        address = ipInterface.composeStr addressParts null;

        # The index must fit into the device part, the per-component check above misses
        # indices beyond the address length (e.g. 2^32 in an IPv4 /0) and negative ones.
        deviceBits = ipInterface.meta.bitWidth - mask;
        validIndex = index >= 0 && (deviceBits >= 63 || index < pow 2 deviceBits);

        result = if !validIndex || any (x: x == null) addressParts then null else address;
      in
      if ipInterface != null && decomposed != null then result else null;

    /**
      A function that calculates the n-th address in the given network.

      # Inputs
      `network` : An IP address representing a network in CIDR notation.
      `index` : An integer representing the index of the desired address within the network.

      # Output
      A string representing the n-th address in the given network, without trailing /mask
      (like `hashedAddress`).

      # Errors
      Throws an error if the input is invalid or the index is out of range.

      # Type
      ```nix
      String -> Int -> String
      ```
    */
    assignAddress =
      network: index:
      let
        result = assignAddress' network index;
      in
      if result != null then
        result
      else
        throw "Invalid input or index out of range: ${toJSON network} with index ${toJSON index}";

    /**
      Reads `length` bits of the hex string `hex`, starting at bit `offset` (most
      significant bit first), as an integer.

      # Type
      ```nix
      String -> Int -> Int -> Int
      ```
    */
    hexBits =
      hex: offset: length:
      foldl (
        acc: bit:
        let
          position = offset + bit;
          nibble = trivial.fromHexString (substring (position / 4) 1 hex);
        in
        acc * 2 + (if bitAnd nibble (pow 2 (3 - mod position 4)) != 0 then 1 else 0)
      ) 0 (genList (bit: bit) length);

    /**
      Replaces the bits `from` (inclusive) to `to` (exclusive) of an address, given as
      its list of components, with the bits of the hex string `hex` starting at bit `offset`
      (most significant bit first). Works per component, so any range of an IPv4 or IPv6
      address can be set.

      # Type
      ```nix
      { meta : { ... }, parts : [ Int ], from : Int, to : Int, hex : String, offset ? Int } -> [ Int ]
      ```
    */
    setBitsFromHex =
      {
        meta,
        parts,
        from,
        to,
        hex,
        offset ? 0,
      }:
      imap0 (
        index: part:
        let
          width = meta.componentBitWidth;
          low = max from (index * width);
          high = min to ((index + 1) * width);
          length = high - low;
          shift = (index + 1) * width - high;
          mask = (pow 2 length - 1) * pow 2 shift;
        in
        if length <= 0 then
          part
        else
          bitOr (bitAnd part (bitXor mask meta.componentMask)) (
            hexBits hex (low - from + offset) length * pow 2 shift
          )
      ) parts;

    /**
      Derives a stable address for a device from its name, inside an IPv4 or IPv6 network,
      e.g. to address hosts, containers or VMs without keeping a list of hand-picked addresses.

      All bits the network leaves free (its device part) are taken from
      SHA-256(`salt` + ":address:" + `name`), so the same inputs always give the same address.

      Distinct names may get the same address, the likelihood increases with fewer free bits.
      Callers handing out several addresses should assert that they are unique and usable (e.g. not a special address).

      # Inputs
      `salt` : A string mixed into the hash.
      `network` : An IPv4 or IPv6 network in CIDR notation, e.g. a /64.
      `name` : The name of the device.

      # Output
      The address, without mask.

      # Example
      ```nix
      hashedAddress { salt = "s"; network = "2001:db8::/64"; name = "host-a"; }
      # "2001:db8::f0a3:42e6:b7cf:1582"
      ```

      # Type
      ```nix
      { salt : String, network : String, name : String } -> String
      ```
    */
    hashedAddress =
      {
        salt,
        network,
        name,
      }:
      let
        decomposed = decompose network;
        meta = decomposed._meta;
        parts = setBitsFromHex {
          inherit meta;
          parts = decomposed.networkParts;
          from = decomposed.mask;
          to = meta.bitWidth;
          hex = hashString "sha256" "${salt}:address:${name}";
        };
      in
      (ip network).composeStr parts null;

    /**
      Derives a stable subnet for `name` out of a larger IPv4 or IPv6 network, e.g. one /64
      per network or host out of a ULA /48.

      The bits between the mask of `network` and `prefixLength` (the subnet ID) are taken
      from SHA-256(`salt` + ":subnet:" + `name`), the remaining bits are zero. The same inputs
      always give the same subnet.

      Distinct names may get the same subnet, the likelihood increases with fewer free bits.
      Callers handing out several subnets should assert that they are unique (see `assertNoOverlap`).

      # Inputs
      `salt` : A string mixed into the hash.
      `network` : An IPv4 or IPv6 network in CIDR notation.
      `name` : The name the subnet is derived for.
      `prefixLength` : The prefix length of the resulting subnet, longer than the mask of `network`.

      # Output
      The subnet in CIDR notation.

      # Errors
      Throws an error if `prefixLength` is not longer than the mask of `network` or exceeds the address length.

      # Example
      ```nix
      hashedSubnet { salt = "s"; network = "fd12:3456:789a::/48"; name = "office"; prefixLength = 64; }
      # "fd12:3456:789a:894d::/64"
      ```

      # Type
      ```nix
      { salt : String, network : String, name : String, prefixLength : Int } -> String
      ```
    */
    hashedSubnet =
      {
        salt,
        network,
        name,
        prefixLength,
      }:
      let
        decomposed = decompose network;
        meta = decomposed._meta;
        parts = setBitsFromHex {
          inherit meta;
          parts = decomposed.networkParts;
          from = decomposed.mask;
          to = prefixLength;
          hex = hashString "sha256" "${salt}:subnet:${name}";
        };
      in
      if prefixLength <= decomposed.mask || prefixLength > meta.bitWidth then
        throw "hashedSubnet: prefixLength ${toString prefixLength} must be longer than the mask ${toString decomposed.mask} of ${toJSON network} and at most ${toString meta.bitWidth}"
      else
        (ip network).composeStr parts prefixLength;

    /**
      Checks whether the given IP address is within the given subnet.

      The address may have a longer mask than the subnet, i.e. the address 1.2.3.4/24 is
      part of the subnet 1.2.0.0/16. To also require the same mask, use `subnetRelation'`.

      # Inputs
      `address` : An IP address that is maybe part of a network.
      `network` : An IP address representing a network.

      # Output
      A boolean indicating whether the address is within the subnet, `false` if the inputs
      are invalid or not of the same kind (IPv4 vs IPv6).

      # Example
      ```nix
      inSubnet' "10.1.2.3" "10.0.0.0/8"
      # true
      ```

      # Type
      ```nix
      String -> String -> Bool
      ```
    */
    inSubnet' =
      address: network:
      let
        result = subnetRelation' address network;
      in
      result == "equal" || result == "subset";

    /**
      Checks whether the given IP address is within the given subnet.
      Same as `inSubnet'`, but throws an error if the inputs are invalid.

      # Inputs
      `address` : An IP address that is maybe part of a network.
      `network` : An IP address representing a network.

      # Output
      A boolean indicating whether the address is within the subnet.

      # Errors
      Throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

      # Example
      ```nix
      inSubnet "fd00::1/64" "fd00::/8"
      # true
      ```

      # Type
      ```nix
      String -> String -> Bool
      ```
    */
    inSubnet =
      address: network:
      let
        result = subnetRelation address network;
      in
      result == "equal" || result == "subset";

    /**
      Returns the broadcast address of an IPv4 network (all device bits set). The mask is
      taken from the input, an address without mask is a /32.

      # Inputs
      `network` : An IPv4 network in CIDR notation, e.g. "10.0.0.0/24". Device bits are ignored.

      # Output
      The broadcast address, without mask.

      # Errors
      Throws an error if the input is invalid or an IPv6 address (IPv6 has no broadcast).

      # Example
      ```nix
      broadcast "10.0.0.0/23"
      # "10.0.1.255"
      ```

      # Type
      ```nix
      String -> String
      ```
    */
    broadcast =
      network:
      let
        decomposed = decompose network;
      in
      if decomposed._meta.name != "ip4" then
        throw "broadcast: IPv6 has no broadcast address, got ${toJSON network}"
      else
        ip4.composeStr (hostRange decomposed).broadcast null;

    /**
      Returns the first usable host address of a network. The mask is taken from the input,
      an address without mask is a /32 (IPv4) or /128 (IPv6).

      IPv4: network address + 1; both addresses of a /31 are usable (RFC 3021), so the
      first host is the network address, a /32 is its only address.
      IPv6: network address + 1, skipping the subnet-router anycast address; for a /127
      (RFC 6164) and a /128 it is the network address.

      # Inputs
      `network` : An IPv4 or IPv6 network in CIDR notation. Device bits are ignored.

      # Output
      The first usable host address, without mask.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      firstHost "10.0.0.0/24"
      # "10.0.0.1"
      ```

      # Type
      ```nix
      String -> String
      ```
    */
    firstHost =
      network:
      let
        range = hostRange (decompose network);
      in
      (ip network).composeStr range.first null;

    /**
      Returns the last usable host address of a network. The mask is taken from the input,
      an address without mask is a /32 (IPv4) or /128 (IPv6).

      IPv4: broadcast address - 1; for a /31 (RFC 3021) the broadcast address, a /32 is its
      only address.
      IPv6: the address with all device bits set (there is no broadcast).

      # Inputs
      `network` : An IPv4 or IPv6 network in CIDR notation. Device bits are ignored.

      # Output
      The last usable host address, without mask.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      lastHost "10.0.0.0/23"
      # "10.0.1.254"
      ```

      # Type
      ```nix
      String -> String
      ```
    */
    lastHost =
      network:
      let
        range = hostRange (decompose network);
      in
      (ip network).composeStr range.last null;

    /**
      Returns the number of usable host addresses of a network, by the same rules as
      `firstHost` and `lastHost`: IPv4 2^n - 2 (n device bits), 2 for a /31 and 1 for a /32;
      IPv6 2^n - 1, 2 for a /127 and 1 for a /128.

      # Inputs
      `network` : An IPv4 or IPv6 network in CIDR notation. Device bits are ignored.

      # Output
      The number of usable host addresses.

      # Errors
      Throws an error if the input is invalid or the count does not fit into a signed 64 bit
      integer (IPv6 networks with more than 63 device bits, i.e. shorter than /65).

      # Example
      ```nix
      hostCount "192.168.0.0/24"
      # 254
      ```

      # Type
      ```nix
      String -> Int
      ```
    */
    hostCount =
      network:
      let
        range = hostRange (decompose network);
        bits = range.deviceBits;
      in
      if bits <= 1 then
        bits + 1
      else if range.meta.name == "ip4" then
        pow 2 bits - 2
      else if bits <= 63 then
        # 2^bits - 1 without overflowing for bits = 63
        (pow 2 (bits - 1) - 1) * 2 + 1
      else
        throw "hostCount: ${toJSON network} has 2^${toString bits} - 1 hosts, which does not fit into a 64 bit integer";

    /**
      Checks whether two networks share at least one address, i.e. their relation (see
      `subnetRelation`) is not "disjoint".

      # Inputs
      `a` : An IP network in CIDR notation.
      `b` : An IP network of the same kind in CIDR notation.

      # Output
      A boolean indicating whether the networks overlap.

      # Errors
      Throws an error if the inputs are invalid or not of the same kind (IPv4 vs IPv6).

      # Example
      ```nix
      overlaps "10.0.0.0/8" "10.1.0.0/16"
      # true
      ```

      # Type
      ```nix
      String -> String -> Bool
      ```
    */
    overlaps = a: b: subnetRelation a b != "disjoint";

    /**
      Asserts that no two addresses of a list are the same, e.g. to validate addresses from
      `hashedAddress`. Addresses are compared by their canonical spelling without mask, so
      "10.0.0.1/24" and "10.0.0.1" are duplicates.

      # Inputs
      `addresses` : A list of IPv4 and/or IPv6 addresses.

      # Output
      The list, unchanged.

      # Errors
      Throws an error listing the duplicates, or if an address is invalid.

      # Example
      ```nix
      assertUniqueAddresses [ "10.0.0.1" "10.0.0.2/24" ]
      # [ "10.0.0.1" "10.0.0.2/24" ]
      ```

      # Type
      ```nix
      [ String ] -> [ String ]
      ```
    */
    assertUniqueAddresses =
      addresses:
      let
        groups = groupBy (address: (decompose address).addressNoMask) addresses;
        duplicates = filterAttrs (key: group: length group > 1) groups;
        describe = key: group: "${key} (${concatMapStringsSep ", " toJSON group})";
      in
      if duplicates == { } then
        addresses
      else
        throw "assertUniqueAddresses: duplicate addresses: ${concatStringsSep "; " (mapAttrsToList describe duplicates)}";

    /**
      Asserts that no two networks of a list overlap (see `overlaps`), e.g. to validate
      subnets from `hashedSubnet`.

      # Inputs
      `networks` : A list of IP networks in CIDR notation, all of the same kind.

      # Output
      The list, unchanged.

      # Errors
      Throws an error listing the overlapping pairs, or if a network is invalid or the
      networks are not all of the same kind (IPv4 vs IPv6).

      # Example
      ```nix
      assertNoOverlap [ "10.0.0.0/24" "10.0.1.0/24" ]
      # [ "10.0.0.0/24" "10.0.1.0/24" ]
      ```

      # Type
      ```nix
      [ String ] -> [ String ]
      ```
    */
    assertNoOverlap =
      networks:
      let
        count = length networks;
        pairs = concatLists (
          genList (
            i:
            genList (j: {
              a = elemAt networks i;
              b = elemAt networks (i + j + 1);
            }) (count - i - 1)
          ) count
        );
        overlapping = filter (pair: overlaps pair.a pair.b) pairs;
      in
      if overlapping == [ ] then
        networks
      else
        throw "assertNoOverlap: overlapping networks: ${
          concatMapStringsSep "; " (pair: "${toJSON pair.a} and ${toJSON pair.b}") overlapping
        }";

    /**
      Checks whether an address is private: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
      (RFC 1918) or fc00::/7 (unique local, RFC 4193). The mask of the input is ignored,
      the address itself is classified. IPv4-mapped IPv6 addresses are not private.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is private.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isPrivate "172.31.0.1"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isPrivate = classifyAddress decompose {
      ip4 = with ip4.special; [
        private10
        private172
        private192
      ];
      ip6 = [ ip6.special.uniqueLocal ];
    };

    /**
      Checks whether an address is a loopback address: 127.0.0.0/8 or ::1. The mask of the
      input is ignored.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is a loopback address.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isLoopback "127.1.2.3"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isLoopback = classifyAddress decompose {
      ip4 = [ ip4.special.loopback ];
      ip6 = [ ip6.special.loopback ];
    };

    /**
      Checks whether an address is link-local: 169.254.0.0/16 or fe80::/10. The mask of the
      input is ignored.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is link-local.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isLinkLocal "fe80::1/64"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isLinkLocal = classifyAddress decompose {
      ip4 = [ ip4.special.linkLocal ];
      ip6 = [ ip6.special.linkLocal ];
    };

    /**
      Checks whether an address is an IPv6 unique local address (fc00::/7, RFC 4193). Always
      false for IPv4. The mask of the input is ignored.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is a unique local address.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isULA "fd12:3456::1"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isULA = classifyAddress decompose {
      ip4 = [ ];
      ip6 = [ ip6.special.uniqueLocal ];
    };

    /**
      Checks whether an address is a multicast address: 224.0.0.0/4 or ff00::/8. The mask
      of the input is ignored.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is a multicast address.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isMulticast "ff02::1"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isMulticast = classifyAddress decompose {
      ip4 = [ ip4.special.multicast ];
      ip6 = [ ip6.special.multicast ];
    };

    /**
      Returns the scope of a multicast address, or null if the address is no multicast
      address. The mask of the input is ignored. IPv4-mapped IPv6 addresses are no multicast
      addresses.

      IPv6 (RFC 4291 2.7, RFC 7346 2): the scope field (the 4th hex digit, bits 12 to 15),
      whatever the flags in the 3rd hex digit, so `ff12::1` is "link" like `ff02::1`. Scopes
      1 "interface", 2 "link", 3 "realm", 4 "admin", 5 "site", 8 "organization", e "global",
      0 and f "reserved", all others "unassigned".

      IPv4 has no scope field, the scope follows from the range: 224.0.0.0/24 (local network
      control block, RFC 5771) is "link", 239.192.0.0/14 (organization local scope, RFC 2365)
      is "organization", the rest of 239.0.0.0/8 (administratively scoped, RFC 2365, including
      the IPv4 local scope 239.255.0.0/16, the smallest administrative scope) is "admin", all
      other multicast addresses are "global".

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      The scope as string, or null if the address is no multicast address.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      multicastScope "ff05::2"
      # "site"
      ```

      # Type
      ```nix
      String -> String | null
      ```
    */
    multicastScope =
      address:
      let
        decomposed = decompose address;
        inIp4 =
          network:
          classifyAddress decompose {
            ip4 = [ network ];
            ip6 = [ ];
          } address;
      in
      if !isMulticast address then
        null
      else if decomposed._meta.name == "ip6" then
        elemAt ip6MulticastScopes (bitAnd (head decomposed.addressParts) 15)
      else if inIp4 ip4.special.localNetworkControl then
        "link"
      else if inIp4 ip4.special.organizationLocal then
        "organization"
      else if inIp4 ip4.special.adminScoped then
        "admin"
      else
        "global";

    /**
      Checks whether an address has link scope: link-local unicast (169.254.0.0/16,
      fe80::/10) or link-scope multicast (224.0.0.0/24, IPv6 multicast with scope 2 and any
      flags, e.g. ff02::1 or ff12::1). The mask of the input is ignored. IPv4-mapped IPv6
      addresses do not have link scope.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address has link scope.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isLinkScope "224.0.0.251"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isLinkScope = address: isLinkLocal address || multicastScope address == "link";

    /**
      Checks whether an address is reserved for documentation: 192.0.2.0/24, 198.51.100.0/24,
      203.0.113.0/24 (RFC 5737), 233.252.0.0/24 (MCAST-TEST-NET, RFC 6676), 2001:db8::/32
      (RFC 3849) or 3fff::/20 (RFC 9637). The mask of the input is ignored. IPv4-mapped IPv6
      addresses are not documentation addresses.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is a documentation address.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isDocumentation "3fff::1"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isDocumentation = classifyAddress decompose {
      ip4 = with ip4.special; [
        documentation1
        documentation2
        documentation3
        mcastTestNet
      ];
      ip6 = with ip6.special; [
        documentation
        documentation2
      ];
    };

    /**
      Checks whether an address is globally reachable, per the "Globally Reachable" column of
      the IANA IPv4 and IPv6 special-purpose address registries. The mask of the input is
      ignored. IPv4-mapped IPv6 addresses are not global (`::ffff:0:0/96` is not globally
      reachable), whatever the embedded IPv4 address.

      Unicast IPv4: every address outside the non-global special blocks (0.0.0.0/8, 10.0.0.0/8,
      100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24,
      192.168.0.0/16, 198.18.0.0/15, 198.51.100.0/24, 203.0.113.0/24,
      240.0.0.0/4), except that 192.0.0.9 and 192.0.0.10 (PCP/TURN anycast) are global.

      Unicast IPv6: only addresses within 2000::/3 and the NAT64 well-known prefix
      64:ff9b::/96 can be global, minus 2001::/23, 2001:db8::/32, 2002::/16 and 3fff::/20,
      except that 2001:1::1, 2001:1::2, 2001:1::3, 2001:3::/32, 2001:4:112::/48, 2001:20::/28
      and 2001:30::/28 are global. Blocks the registry marks "N/A" (Teredo 2001::/32, 6to4
      2002::/16) are not global.

      Multicast (not covered by the registries): global if `multicastScope` is "global" and
      the address is no documentation address (233.252.0.0/24), so e.g. ff0e::1 and
      232.1.1.1 are global, ff05::2, 224.0.0.251 and 239.1.1.1 are not.

      # Inputs
      `address` : An IPv4 or IPv6 address.

      # Output
      A boolean indicating whether the address is globally reachable.

      # Errors
      Throws an error if the input is invalid.

      # Example
      ```nix
      isGlobal "2001:4860:4860::8888"
      # true
      ```

      # Type
      ```nix
      String -> Bool
      ```
    */
    isGlobal =
      address:
      let
        inRanges = ranges: classifyAddress decompose ranges address;
      in
      if isMulticast address then
        multicastScope address == "global" && !isDocumentation address
      else
        (inRanges globalRanges.space && !inRanges globalRanges.nonGlobal)
        || inRanges globalRanges.exceptions;

    /**
      Checks whether the given value is a valid NAT64 prefix (RFC 6052 2.2): an IPv6 network
      with explicit mask of 32, 40, 48, 56, 64 or 96, no device bits set, and bits 64 to 71
      (the "u" octet) zero.

      # Inputs
      `prefix` : The value to check.

      # Output
      A boolean indicating whether the input is a valid NAT64 prefix.

      # Example
      ```nix
      checkNat64Prefix "64:ff9b::/96"
      # true
      checkNat64Prefix "2001:db8::/80"
      # false
      ```

      # Type
      ```nix
      Any -> Bool
      ```
    */
    checkNat64Prefix =
      prefix:
      let
        decomposed = ip6.decompose' prefix;
      in
      decomposed != null
      && hasInfix "/" prefix
      && elem decomposed.mask [
        32
        40
        48
        56
        64
        96
      ]
      && decomposed.addressParts == decomposed.networkParts
      && bitAnd (elemAt decomposed.addressParts 4) 65280 == 0;

    /**
      Embeds an IPv4 address into an IPv6 address under a NAT64 prefix as defined in
      RFC 6052 2.2, e.g. to compute the IPv6 address under which a NAT64 makes
      an IPv4 host reachable. Returns `null` if the input is invalid, see `nat64Address`.

      # Inputs
      `prefix` : A NAT64 prefix (see `checkNat64Prefix`), defaults to the well-known prefix `64:ff9b::/96`.
      `address` : An IPv4 address, its mask is ignored.

      # Output
      The IPv6 address without mask, or `null`.

      # Type
      ```nix
      { prefix ? String, address : String } -> String | null
      ```
    */
    nat64Address' =
      args:
      let
        result = nat64Embed args;
      in
      if result.error == null then result.value else null;

    /**
      Embeds an IPv4 address into an IPv6 address under a NAT64 prefix as defined in
      RFC 6052 2.2. For prefixes shorter than /96 the IPv4 address is split around bits 64
      to 71, which stay zero.

      # Inputs
      `prefix` : A NAT64 prefix (see `checkNat64Prefix`), defaults to the well-known prefix `64:ff9b::/96`.
      `address` : An IPv4 address, its mask is ignored.

      # Output
      The IPv6 address without mask.

      # Errors
      Throws an error if the prefix or the address is invalid, or if the well-known prefix is
      used with a non-global IPv4 address (private, shared, loopback, link-local or
      "this network"), which RFC 6052 3.1 forbids; use a network-specific prefix such as
      `ip6.special.nat64Local` (64:ff9b:1::/48) for those.

      # Example
      ```nix
      nat64Address { address = "192.0.2.33"; }
      # "64:ff9b::c000:221"
      nat64Address { prefix = "2001:db8:100::/40"; address = "192.0.2.33"; }
      # "2001:db8:1c0:2:21::"
      ```

      # Type
      ```nix
      { prefix ? String, address : String } -> String
      ```
    */
    nat64Address =
      args:
      let
        result = nat64Embed args;
      in
      if result.error == null then result.value else throw "nat64Address: ${result.error}";

    /**
      Extracts the IPv4 address embedded into an IPv6 address under a NAT64 prefix
      (RFC 6052 2.2), the inverse of `nat64Address`. The suffix bits are ignored.

      # Inputs
      `prefix` : A NAT64 prefix (see `checkNat64Prefix`), defaults to the well-known prefix `64:ff9b::/96`.
      `address` : An IPv6 address within `prefix`, its mask is ignored.

      # Output
      The IPv4 address without mask, or `null` if an input is invalid, the address does
      not lie within the prefix, or its bits 64 to 71 are not zero.

      # Type
      ```nix
      { prefix ? String, address : String } -> String | null
      ```
    */
    nat64Extract' =
      {
        prefix ? ip6.special.nat64,
        address,
      }:
      let
        v6 = ip6.decompose' address;
        mapping = nat64Mapping prefix;
      in
      if
        v6 == null
        || !checkNat64Prefix prefix
        || !inSubnet' v6.addressNoMask mapping.ip6.network
        || (mapping.ip6.mask != 96 && bitAnd (elemAt v6.addressParts 4) 65280 != 0)
      then
        null
      else
        mapAddress {
          inherit mapping;
          fromSide = "ip6";
          toSide = "ip4";
          address = v6;
        };

    /**
      Like `nat64Extract'`, but throws an error instead of returning `null`.

      # Example
      ```nix
      nat64Extract { address = "64:ff9b::c000:221"; }
      # "192.0.2.33"
      ```

      # Type
      ```nix
      { prefix ? String, address : String } -> String
      ```
    */
    nat64Extract =
      args:
      let
        result = nat64Extract' args;
      in
      if result != null then
        result
      else
        throw "nat64Extract: invalid input or ${toJSON args.address} is no NAT64 address within ${
          toJSON (args.prefix or ip6.special.nat64)
        }";

    /**
      Returns the reverse DNS name of an address or network. For an address without mask,
      the full PTR name; for a network, the name of its reverse zone (labels of the network
      address up to the mask). The device bits of a network are ignored.

      # Inputs
      `address` : An IPv4 or IPv6 address, optionally with mask.

      # Output
      The domain name under in-addr.arpa (IPv4) or ip6.arpa (IPv6), without trailing dot.

      # Errors
      Throws an error if the input is invalid or the mask is not a multiple of 8 (IPv4) or
      4 (IPv6), since only those have a reverse zone of their own.

      # Example
      ```nix
      toArpa "1.2.3.4"
      # "4.3.2.1.in-addr.arpa"
      toArpa "2001:db8::/32"
      # "8.b.d.0.1.0.0.2.ip6.arpa"
      ```

      # Type
      ```nix
      String -> String
      ```
    */
    toArpa =
      address:
      let
        decomposed = decompose address;
        isIp4 = decomposed._meta.name == "ip4";
        labelBits = if isIp4 then 8 else 4;
        suffix = if isIp4 then "in-addr.arpa" else "ip6.arpa";
        hexDigit = n: toLower (trivial.toHexString n);
        nibbles =
          part:
          map hexDigit [
            (part / 4096)
            (mod (part / 256) 16)
            (mod (part / 16) 16)
            (mod part 16)
          ];
        allLabels =
          if isIp4 then map toString decomposed.networkParts else concatMap nibbles decomposed.networkParts;
        labels = reverseList (take (decomposed.mask / labelBits) allLabels);
      in
      if mod decomposed.mask labelBits != 0 then
        throw "toArpa: the mask of ${toJSON address} is not a multiple of ${toString labelBits}"
      else
        concatStringsSep "." (labels ++ [ suffix ]);

    /**
      Builds a SLAAC address of an IPv6 /64 network from a MAC address, using the modified
      EUI-64 interface identifier (RFC 4291 2.5.1, appendix A): the universal/local bit
      (0x02 of the first byte) is flipped and ff:fe is inserted between the third and the
      fourth byte.

      # Inputs
      `network` : An IPv6 network with mask exactly 64, e.g. "2001:db8::/64".
      `mac` : A MAC address, e.g. "52:54:00:12:34:56".

      # Output
      The address, without mask.

      # Errors
      Throws an error if the network is invalid, not IPv6 or its mask is not 64, or if the
      MAC address is invalid.

      # Example
      ```nix
      eui64FromMac { network = "2001:db8::/64"; mac = "52:54:00:12:34:56"; }
      # "2001:db8::5054:ff:fe12:3456"
      ```

      # Type
      ```nix
      { network : String, mac : String } -> String
      ```
    */
    eui64FromMac =
      { network, mac }:
      let
        decomposed = decompose network;
        bytes = macToParts mac;
        byte = elemAt bytes;
        interfaceId = [
          ((bitXor (byte 0) 2) * 256 + byte 1)
          (byte 2 * 256 + 255)
          (254 * 256 + byte 3)
          (byte 4 * 256 + byte 5)
        ];
      in
      if decomposed._meta.name != "ip6" || decomposed.mask != 64 then
        throw "eui64FromMac: network must be an IPv6 /64, got ${toJSON network}"
      else
        ip6.composeStr (take 4 decomposed.networkParts ++ interfaceId) null;

    /**
      Compares two addresses: IPv4 sorts before IPv6, then by address value, then by mask
      (shorter first; an address without mask has the full-length mask).

      # Inputs
      `a` : An IPv4 or IPv6 address, optionally with mask.
      `b` : An IPv4 or IPv6 address, optionally with mask.

      # Output
      -1 if `a` sorts before `b`, 0 if they are equal, 1 otherwise.

      # Errors
      Throws an error if an input is invalid.

      # Example
      ```nix
      compareAddresses "10.0.0.2" "10.0.0.10"
      # -1
      ```

      # Type
      ```nix
      String -> String -> Int
      ```
    */
    compareAddresses =
      a: b:
      let
        compareInts =
          x: y:
          if x < y then
            -1
          else if x > y then
            1
          else
            0;
        key =
          address:
          let
            decomposed = decompose address;
          in
          [ (if decomposed._meta.name == "ip4" then 0 else 1) ]
          ++ decomposed.addressParts
          ++ [ decomposed.mask ];
        keyA = key a;
        keyB = key b;
      in
      # Keys of different families differ in their first element, so compareLists never
      # compares past it
      compareLists compareInts keyA keyB;

    /**
      Sorts a list of addresses by `compareAddresses`: IPv4 before IPv6, then by address
      value, then by mask.

      # Inputs
      `addresses` : A list of IPv4 and/or IPv6 addresses, optionally with mask.

      # Output
      The sorted list, with the addresses spelled as in the input.

      # Errors
      Throws an error if an address is invalid.

      # Example
      ```nix
      sortAddresses [ "::1" "10.0.0.10" "10.0.0.2" ]
      # [ "10.0.0.2" "10.0.0.10" "::1" ]
      ```

      # Type
      ```nix
      [ String ] -> [ String ]
      ```
    */
    sortAddresses =
      addresses:
      foldl' (acc: address: seq (decompose address) acc) (sort (
        a: b: compareAddresses a b < 0
      ) addresses) addresses;

    /**
      Decomposes an endpoint, i.e. an IP address without mask plus a port, into its parts.
      IPv4 endpoints are written "1.2.3.4:53", IPv6 endpoints "[2001:db8::1]:53". The port
      must be a decimal number from 0 to 65535 without leading zeros.

      # Input
      `endpoint` : An endpoint string, e.g. "[2001:DB8::1]:53".

      # Output
      An attribute set with the following fields, or `null` if the input is invalid:
      - `address`: The address in canonical spelling, without mask, e.g. "2001:db8::1".
      - `port`: The port as an integer.
      - `family`: "ip4" or "ip6".

      # Type
      ```nix
      String -> { address : String, port : Int, family : String } | null
      ```
    */
    decomposeEndpoint' =
      endpoint:
      let
        isString = typeOf endpoint == "string";
        ip4Match = if isString then match "([0-9.]+):([0-9]+)" endpoint else null;
        ip6Match = if isString then match "\\[([0-9a-fA-F:.]+)]:([0-9]+)" endpoint else null;
        parsed =
          if ip4Match != null then
            {
              interface = ip4;
              parts = ip4Match;
            }
          else if ip6Match != null then
            {
              interface = ip6;
              parts = ip6Match;
            }
          else
            null;
        address = elemAt parsed.parts 0;
        port = elemAt parsed.parts 1;
        validPort = match "0|[1-9][0-9]{0,4}" port != null && toInt port <= 65535;
      in
      if parsed == null || !(parsed.interface.checkNoMask address) || !validPort then
        null
      else
        {
          address = (parsed.interface.decompose address).addressNoMask;
          port = toInt port;
          family = parsed.interface.meta.name;
        };

    /**
      Decomposes an endpoint, i.e. an IP address without mask plus a port, into its parts.
      Same as `decomposeEndpoint'`, but throws an error if the input is invalid.

      # Input
      `endpoint` : An endpoint string, e.g. "1.2.3.4:53" or "[2001:db8::1]:53".

      # Output
      An attribute set `{ address; port; family; }`, see `decomposeEndpoint'`.

      # Errors
      Throws an error if the input is not a valid endpoint.

      # Type
      ```nix
      String -> { address : String, port : Int, family : String }
      ```
    */
    decomposeEndpoint =
      endpoint:
      let
        result = decomposeEndpoint' endpoint;
      in
      if result != null then result else throw "Invalid endpoint: ${toJSON endpoint}";

    /**
      Checks if the given value is a MAC address: six groups of two hexadecimal digits
      (case-insensitive), consistently separated by either ":" or "-", e.g. "00:1A:2b:3c:4d:5e".

      # Input
      `val` : The value to check.

      # Output
      A boolean indicating whether the input is a valid MAC address.

      # Type
      ```nix
      String -> Bool
      ```
    */
    checkMac =
      val:
      typeOf val == "string"
      && (
        match "[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}" val != null
        || match "[0-9a-fA-F]{2}(-[0-9a-fA-F]{2}){5}" val != null
      );

    /**
      Splits a MAC address into its six bytes.

      # Input
      `mac` : A MAC address, e.g. "00:1a:2b:3c:4d:5e", see `checkMac`.

      # Output
      A list of six integers, e.g. [ 0 26 43 60 77 94 ], or `null` if the input is invalid.

      # Type
      ```nix
      String -> [ Int ] | null
      ```
    */
    macToParts' =
      mac:
      if !(checkMac mac) then null else map trivial.fromHexString (splitString (substring 2 1 mac) mac);

    /**
      Splits a MAC address into its six bytes.
      Same as `macToParts'`, but throws an error if the input is invalid.

      # Input
      `mac` : A MAC address, e.g. "00:1a:2b:3c:4d:5e", see `checkMac`.

      # Output
      A list of six integers, e.g. [ 0 26 43 60 77 94 ].

      # Errors
      Throws an error if the input is not a valid MAC address.

      # Type
      ```nix
      String -> [ Int ]
      ```
    */
    macToParts =
      mac:
      let
        result = macToParts' mac;
      in
      if result != null then result else throw "Invalid MAC address: ${toJSON mac}";

    /**
      Computes the prefix length of a netmask, e.g. "255.255.255.0" -> 24 or
      "ffff:ffff::" -> 32. The family is detected automatically. The netmask must not
      have a trailing /mask and must be contiguous (ones followed by zeros).

      # Input
      `netmask` : An IPv4 or IPv6 netmask, e.g. "255.255.255.0".

      # Output
      The prefix length as an integer, or `null` if the input is invalid or not contiguous.

      # Type
      ```nix
      String -> Int | null
      ```
    */
    prefixFromNetmask' =
      netmask:
      let
        interface = ip' netmask;
        parts = (interface.decompose netmask).addressParts;
        prefixes = genList (i: i) (interface.meta.bitWidth + 1);
      in
      if interface == null || !(interface.checkNoMask netmask) then
        null
      else
        findFirst (prefix: interface.calculateNetworkMaskParts prefix == parts) null prefixes;

    /**
      Computes the prefix length of a netmask, e.g. "255.255.255.0" -> 24.
      Same as `prefixFromNetmask'`, but throws an error if the input is invalid.

      # Input
      `netmask` : An IPv4 or IPv6 netmask, e.g. "255.255.255.0".

      # Output
      The prefix length as an integer.

      # Errors
      Throws an error if the input is not a valid, contiguous netmask without /mask.

      # Type
      ```nix
      String -> Int
      ```
    */
    prefixFromNetmask =
      netmask:
      let
        result = prefixFromNetmask' netmask;
      in
      if result != null then result else throw "Invalid netmask: ${toJSON netmask}";

    /**
      A function that takes an IP address and returns the appropriate interface of functions to process it, or null if invalid.

      # Input
      `address` : An IP address, which can be either an IPv4 or IPv6 address.

      # Output
      The ip4 or ip6 interface depending on the type of the input IP address, or null if invalid.

      # Type
      ```nix
      String -> { ... } | null
      ```
      *
    */
    ip' =
      address:
      if ip4.check address then
        ip4
      else if ip6.check address then
        ip6
      else
        null;

    /**
      A function that takes an IP address and returns the appropriate interface of functions to process it.

      # Input
      `address` : An IP address, which can be either an IPv4 or IPv6 address.

      # Output
      The ip4 or ip6 interface depending on the type of the input IP address.

      # Errors
      Throws an error if the input is not a valid IP address.

      # Type
      ```nix
      String -> { ... }
      ```
      *
    */
    ip =
      address:
      let
        result = ip' address;
      in
      if result != null then result else throw "Invalid IP address: ${toJSON address}";

    ipN = meta: rec {
      /**
        Converts an IP address represented as list of integers to its string representation in CIDR notation.

        # Input
        `addressParts` : A list of integers representing the IP address in its components, e.g. [1, 2, 3, 4]
        `mask` : An integer representing the CIDR mask.

        # Output
        A string representing the IP address in CIDR notation

        # Type
        ```nix
        [ Int ] -> Int | null -> String
        ```
      */
      composeStr =
        addressParts: mask:
        if mask != null then
          "${meta.partsToStr addressParts}/${toString mask}"
        else
          "${meta.partsToStr addressParts}";

      /**
        Computes the network mask list for an IP address given a CIDR mask.

        # Input
        `mask` : An integer representing the CIDR mask.

        # Output
        A list of integers representing the network mask for the given CIDR mask.

        # Type
        ```nix
        Int -> [ Int ]
        ```
      */
      calculateNetworkMaskParts =
        mask:
        if !checkIpMask mask then
          throw "Illegal arguments"
        else
          genList (
            i:
            let
              startOfComponent = i * meta.componentBitWidth;
              endOfComponent = startOfComponent + meta.componentBitWidth;
              bitsInComponent = max (min (mask - startOfComponent) meta.componentBitWidth) 0;
            in
            if mask <= startOfComponent then
              0
            else if mask >= endOfComponent then
              meta.componentMask
            else
              (rep2Add bitsInComponent 1) * pow 2 (meta.componentBitWidth - bitsInComponent)
          ) meta.components;

      /**
        Computes the device mask for an IP address given a CIDR mask.

        # Input
        `mask` : An integer representing the CIDR mask.

        # Output
        An list of integers representing the device mask for the given CIDR mask.

        # Type
        ```nix
        Int -> [ Int ]
        ```
      */
      calculateDeviceMaskParts =
        mask: map (part: bitAnd (bitNot part) meta.componentMask) (calculateNetworkMaskParts mask);

      /**
        Decomposes an IP address in CIDR notation into its components.
        Same as `decompose`, but returns `null` if the input is invalid.

        # Input
        `val` : A string representing the IP address in CIDR notation, e.g. "1.2.3.4/32".

        # Output
        An attribute set containing the following fields:
        - `addressParts`: A list of integers representing the IP address in its components, e.g. [1, 2, 3, 4].
        - `address`: The normalized IP address in CIDR notation as a string.
        - `addressNoMask`: The normalized IP address without trailing /mask as a string.
        - `networkParts`: A list of integers representing the network part of the IP address.
        - `network`: The network part of the IP address as string.
        - `networkNoMask`: The network part of the IP address without trailing /mask as a string.
        - `deviceParts`: A list of integers representing the device part of the IP address.
        - `device`: The device part of the IP address as string.
        - `deviceNoMask`: The device part of the IP address without trailing /mask as a string.
        - `networkMaskParts`: A list of integers representing the network mask for the given CIDR mask.
        - `networkMask`: The network mask as a string.
        - `networkMaskNoMask`: The network mask without trailing /mask as a string.
        - `mask`: The CIDR mask as an integer.
        - `_meta`: Information about the IP type

        If the input is invalid, it will return `null`

        # Type
        ```nix
        String -> { addressParts : [ Int ], address : String, networkParts : [ Int ], network : String, deviceParts : [ Int ], device : String, mask : Int } | null
        ```
      */
      decompose' =
        val:
        let
          validString = typeOf val == "string";

          parts = splitString "/" val;
          address = head parts;
          mask = if length parts > 1 then last parts else toString meta.bitWidth;
          validMask = length parts <= 2 && checkDecimal mask && toInt mask <= meta.bitWidth;

          chunkedAddress = meta.strToParts address;
          validAddressPart =
            chunkedAddress != null
            && length chunkedAddress == meta.components
            && all (
              part:
              let
                partInt = meta.componentFromString part;
              in
              meta.componentIsValidString part && partInt >= 0 && partInt <= meta.componentMask
            ) chunkedAddress;

          chunks = map meta.componentFromString chunkedAddress;
          maskInt = toInt mask;
          networkMask = calculateNetworkMaskParts maskInt;
          deviceMask = calculateDeviceMaskParts maskInt;

          networkPart = partsBitAnd chunks networkMask;
          devicePart = partsBitAnd chunks deviceMask;

          compose = adr: composeStr adr maskInt;
          composeNoMask = adr: composeStr adr null;
        in
        if validString && validMask && validAddressPart then
          {
            addressParts = chunks;
            address = compose chunks;
            addressNoMask = composeNoMask chunks;
            networkParts = networkPart;
            network = compose networkPart;
            networkNoMask = composeNoMask networkPart;
            deviceParts = devicePart;
            device = compose devicePart;
            deviceNoMask = composeNoMask devicePart;
            networkMaskParts = networkMask;
            networkMask = compose networkMask;
            networkMaskNoMask = composeNoMask networkMask;
            mask = maskInt;
            _meta = meta;
          }
        else
          null;

      /**
        Decomposes an IP address in CIDR notation into its components.
        Same as `decompose'`, but throws an error if the input is invalid.

        # Input
        `val` : A string representing the IP address in CIDR notation, e.g. "1.2.3.4/32".

        # Output
        An attribute set containing the following fields:
        - `addressParts`: A list of integers representing the IP address in its components, e.g. [1, 2, 3, 4].
        - `address`: The normalized IP address in CIDR notation as a string.
        - `addressNoMask`: The normalized IP address without trailing /mask as a string.
        - `networkParts`: A list of integers representing the network part of the IP address.
        - `network`: The network part of the IP address as string.
        - `networkNoMask`: The network part of the IP address without trailing /mask as a string.
        - `deviceParts`: A list of integers representing the device part of the IP address.
        - `device`: The device part of the IP address as string.
        - `deviceNoMask`: The device part of the IP address without trailing /mask as a string.
        - `networkMaskParts`: A list of integers representing the network mask for the given CIDR mask.
        - `networkMask`: The network mask as a string.
        - `networkMaskNoMask`: The network mask without trailing /mask as a string.
        - `mask`: The CIDR mask as an integer.
        If the input is invalid, it will throw an error.

        # Type
        ```nix
        String -> { addressParts : [ Int ], address : String, networkParts : [ Int ], network : String, deviceParts : [ Int ], device : String, mask : Int }
        ```
      */
      decompose =
        val:
        let
          result = decompose' val;
        in
        if result != null then result else throw "Invalid ${meta.description}: ${toJSON val}";

      /**
        Checks if the given value is a valid IP address represented as an list of integers.

        # Input
        `val` : A list of integers representing the IP address in its components, e.g. [1, 2, 3, 4]

        # Output
        A boolean indicating whether the input is a valid IP address represented as an list of integers.

        # Type
        ```nix
        [ Int ] -> Bool
        ```
      */
      checkIpParts =
        val:
        typeOf val == "list"
        && all (part: typeOf part == "int" && part >= 0 && part <= meta.componentMask) val
        && length val == meta.components;

      /**
        Checks if the given value is a valid IP mask.

        # Input
        `val` : An integer representing the CIDR mask.

        # Output
        A boolean indicating whether the input is a valid IP mask.

        # Type
        ```nix
        Int -> Bool
        ```
      */
      checkIpMask = mask: typeOf mask == "int" && mask >= 0 && mask <= meta.bitWidth;

      /**
        Checks if the given value is a valid IP address in CIDR notation. The IP
        address must be normalized, i.e. no device part is present.

        # Input
        `val` : A string representing the IP address in CIDR notation

        # Output
        A boolean indicating whether the input is a valid IP address in CIDR notation
        without device part.

        # Type
        ```nix
        String -> Bool
        ```
      */
      checkNormalizedNetwork =
        val:
        let
          result = decompose' val;
        in
        result != null && result.addressParts == result.networkParts;

      /**
        Checks if the given value is a valid IP address in CIDR notation.

        # Input
        `val` : A string representing the IP address in CIDR notation, e.g. "1.2.3.4/32".

        # Output
        A boolean indicating whether the input is a valid IP address in CIDR notation.

        # Type
        ```nix
        String -> Bool
        ```
      */
      check = val: decompose' val != null;

      /**
        Checks if the given value is a valid IP address without trailing /mask. Any valid
        spelling is accepted, e.g. "2001:DB8:0::1"; use `checkCanonical` to require the
        canonical one.

        # Input
        `val` : A string representing the IP address, e.g. "1.2.3.4".

        # Output
        A boolean indicating whether the input is a valid IP address without trailing /mask.

        # Type
        ```nix
        String -> Bool
        ```
      */
      checkNoMask = val: check val && !(hasInfix "/" val);

      /**
        Checks if the given value is a valid IP address in CIDR notation with trailing /mask.

        # Input
        `val` : A string representing the IP address in CIDR notation, e.g. "1.2.3.4/32"

        # Output
        A boolean indicating whether the input is a valid IP address in CIDR notation with trailing /mask.
        Any valid spelling is accepted, e.g. "2001:DB8:0::1/64"; use `checkCanonical` to
        require the canonical one.

        # Type
        ```nix
        String -> Bool
        ```
      */
      checkWithMask = val: check val && hasInfix "/" val;

      /**
        Checks if the given value is a valid IP address in its canonical spelling (RFC 5952
        for IPv6), with or without trailing /mask, e.g. "2001:db8::1" but not "2001:DB8:0::1".

        # Input
        `val` : A string representing the IP address, e.g. "2001:db8::1/64".

        # Output
        A boolean indicating whether the input is a valid IP address in canonical spelling.

        # Type
        ```nix
        String -> Bool
        ```
      */
      checkCanonical =
        val:
        let
          result = decompose' val;
        in
        result != null && (result.address == val || result.addressNoMask == val);

      /**
        Computes the netmask for a prefix length, e.g. `ip4.netmaskFromPrefix 24` is
        "255.255.255.0" and `ip6.netmaskFromPrefix 32` is "ffff:ffff::".

        # Input
        `prefix` : The prefix length, from 0 to the address bit width.

        # Output
        The netmask as a string, without trailing /mask.

        # Errors
        Throws an error if the prefix length is out of range.

        # Type
        ```nix
        Int -> String
        ```
      */
      netmaskFromPrefix =
        prefix:
        if !checkIpMask prefix then
          throw "Invalid prefix length for ${meta.description}: ${toJSON prefix}"
        else
          composeStr (calculateNetworkMaskParts prefix) null;

      /**
        Spells out an address in full: for IPv6 all eight components with four lower case
        hexadecimal digits each and no "::" compression (nor dotted IPv4 notation). For
        IPv4 this is the canonical dotted quad, octets are not zero-padded since leading
        zeros are ambiguous (RFC 6943 3.1.1). The trailing /mask is kept if and only if the
        input has one.

        # Input
        `val` : An IP address, e.g. "2001:db8::1/64".

        # Output
        The expanded address, e.g. "2001:0db8:0000:0000:0000:0000:0000:0001/64".

        # Errors
        Throws an error if the input is invalid.

        # Example
        ```nix
        ip6.expand "::ffff:192.0.2.1"
        # "0000:0000:0000:0000:0000:ffff:c000:0201"
        ```

        # Type
        ```nix
        String -> String
        ```
      */
      expand =
        val:
        let
          decomposed = decompose val;
          pad = str: if meta.name == "ip6" then fixedWidthString 4 "0" str else str;
          expanded = concatMapStringsSep meta.componentSeparator (
            part: pad (meta.componentToString part)
          ) decomposed.addressParts;
        in
        if hasInfix "/" val then "${expanded}/${toString decomposed.mask}" else expanded;

      /**
        Well-known special-purpose networks of the address family, as normalized networks in
        CIDR notation, e.g. `ip6.special.documentation` is `"2001:db8::/32"`. Contains the most
        important entries of the IANA special-purpose address registries (RFC 6890 and its
        updates) plus multicast. Entries may be nested, e.g. the
        globally reachable PCP/TURN anycast addresses inside the IETF protocol assignments.

        # Type
        ```nix
        { <name> : String }
        ```
      */
      inherit (meta) special;

      inherit meta;
    };

    ip4 = ipN rec {
      components = 4; # In string representation, how many parts an IPv4 address has
      componentMask = 255; # Maximum value for each component
      componentBitWidth = 8; # Bit width of each component
      componentSeparator = "."; # In string representation, how components are separated
      description = "IPv4 address"; # Description of the IP type
      name = "ip4"; # Name of the IP type
      bitWidth = 32; # Total bit width of an IPv4 address
      componentIsValidString = checkDecimal; # Function to check if a string is a valid component
      componentFromString = toInt; # Function to convert a component string to an integer
      componentToString = toString; # Function to convert a component integer to a string
      strToParts = splitString "."; # Function to split a string representation of an IP address into its components
      partsToStr =
        addressParts: concatStringsSep componentSeparator (map componentToString addressParts); # Function to convert a list of components to a string representation
      special = {
        thisNetwork = "0.0.0.0/8"; # RFC 791
        private10 = "10.0.0.0/8"; # RFC 1918
        sharedAddressSpace = "100.64.0.0/10"; # RFC 6598, carrier-grade NAT
        loopback = "127.0.0.0/8"; # RFC 1122
        linkLocal = "169.254.0.0/16"; # RFC 3927
        private172 = "172.16.0.0/12"; # RFC 1918
        ietfProtocolAssignments = "192.0.0.0/24"; # RFC 6890, contains e.g. DS-Lite, PCP/TURN anycast, NAT64 discovery
        pcpAnycast = "192.0.0.9/32"; # RFC 7723, Port Control Protocol anycast, globally reachable
        turnAnycast = "192.0.0.10/32"; # RFC 8155, TURN anycast, globally reachable
        documentation1 = "192.0.2.0/24"; # RFC 5737, TEST-NET-1
        as112 = "192.31.196.0/24"; # RFC 7535, AS112-v4
        amt = "192.52.193.0/24"; # RFC 7450, Automatic Multicast Tunneling
        private192 = "192.168.0.0/16"; # RFC 1918
        as112DirectDelegation = "192.175.48.0/24"; # RFC 7534, direct delegation AS112 service
        benchmarking = "198.18.0.0/15"; # RFC 2544
        documentation2 = "198.51.100.0/24"; # RFC 5737, TEST-NET-2
        documentation3 = "203.0.113.0/24"; # RFC 5737, TEST-NET-3
        multicast = "224.0.0.0/4"; # RFC 5771
        localNetworkControl = "224.0.0.0/24"; # RFC 5771, link-scope multicast, never forwarded
        mcastTestNet = "233.252.0.0/24"; # RFC 6676, MCAST-TEST-NET, multicast documentation
        adminScoped = "239.0.0.0/8"; # RFC 2365, administratively scoped multicast
        organizationLocal = "239.192.0.0/14"; # RFC 2365, IPv4 organization local scope
        localScope = "239.255.0.0/16"; # RFC 2365, IPv4 local scope (smallest administrative scope)
        reserved = "240.0.0.0/4"; # RFC 1112
        limitedBroadcast = "255.255.255.255/32"; # RFC 919, lies within `reserved`
      };
    };

    ip6 = ipN rec {
      components = 8; # In string representation, how many parts an IPv6 address has
      componentMask = 65535; # Maximum value for each component
      componentBitWidth = 16; # Bit width of each component
      componentSeparator = ":"; # In string representation, how components are separated
      description = "IPv6 address"; # Description of the IP type
      name = "ip6"; # Name of the IP type
      bitWidth = 128; # Total bit width of an IPv6 address
      componentIsValidString = checkHex; # Function to check if a string is a valid component
      componentFromString = trivial.fromHexString; # Function to convert a component string to an integer
      componentToString = x: strings.toLower (trivial.toHexString x); # Function to convert a component integer to a string
      strToParts =
        str:
        let
          str' = ip6EmbeddedIp4 ip4 str;
        in
        if str' == null then null else ipGapSplit ip6.meta str'; # Function to split a string representation of an IP address into its components
      partsToStr = ipGapJoin ip6.meta; # Function to convert a list of components to a string representation
      special = {
        unspecified = "::/128"; # RFC 4291
        loopback = "::1/128"; # RFC 4291
        ipv4Mapped = "::ffff:0.0.0.0/96"; # RFC 4291, ::ffff:0:0/96
        ipv4Translated = "::ffff:0:0:0/96"; # RFC 2765 (SIIT), ::ffff:0:a.b.c.d, dropped by RFC 6145, not in the IANA registry
        nat64 = "64:ff9b::/96"; # RFC 6052, IPv4/IPv6 translation well-known prefix
        nat64Local = "64:ff9b:1::/48"; # RFC 8215, local-use IPv4/IPv6 translation
        discardOnly = "100::/64"; # RFC 6666
        globalUnicast = "2000::/3"; # RFC 4291 2.4, IANA global unicast allocations, contains the blocks up to `documentation2`
        ietfProtocolAssignments = "2001::/23"; # RFC 2928, contains e.g. Teredo, benchmarking, PCP/TURN anycast
        teredo = "2001::/32"; # RFC 4380
        pcpAnycast = "2001:1::1/128"; # RFC 7723, Port Control Protocol anycast, globally reachable
        turnAnycast = "2001:1::2/128"; # RFC 8155, TURN anycast, globally reachable
        dnsSdSrpAnycast = "2001:1::3/128"; # RFC 9665, DNS-SD Service Registration Protocol anycast, globally reachable
        benchmarking = "2001:2::/48"; # RFC 5180
        amt = "2001:3::/32"; # RFC 7450, Automatic Multicast Tunneling, globally reachable
        as112 = "2001:4:112::/48"; # RFC 7535, AS112-v6, globally reachable
        orchidV2 = "2001:20::/28"; # RFC 7343, ORCHIDv2, globally reachable
        droneRemoteId = "2001:30::/28"; # RFC 9374, Drone Remote ID Protocol Entity Tags (DETs), globally reachable
        documentation = "2001:db8::/32"; # RFC 3849
        sixToFour = "2002::/16"; # RFC 3056
        as112DirectDelegation = "2620:4f:8000::/48"; # RFC 7534, direct delegation AS112 service
        documentation2 = "3fff::/20"; # RFC 9637
        srv6Sid = "5f00::/16"; # RFC 9602, SRv6 segment identifiers
        uniqueLocal = "fc00::/7"; # RFC 4193
        linkLocal = "fe80::/10"; # RFC 4291
        multicast = "ff00::/8"; # RFC 4291
        linkLocalMulticast = "ff02::/16"; # RFC 4291 2.7, link scope with flags 0 only, ff12::/16 etc. are link scope too
        solicitedNode = "ff02::1:ff00:0/104"; # RFC 4291 2.7.1, solicited-node multicast
      };
    };

    types = import ./types.nix {
      inherit
        lib
        ip4
        ip6
        subnetRelation'
        decompose'
        decomposeEndpoint'
        checkMac
        prefixFromNetmask'
        checkNat64Prefix
        ;
    };
  };
in
self
