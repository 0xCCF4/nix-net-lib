{ nixpkgs ? import <nixpkgs> { }
, lib ? nixpkgs.lib
, ...
}@inputs:
with builtins; with lib;
let
  rep2Add = mask: val:
    if mask == 0 then
      0
    else
      2 * (rep2Add (mask - 1) val) + val;

  # Decimal number of at most three digits, without leading zeros. Used for IPv4 octets
  # (RFC 6943 3.1.1: leading zeros are ambiguous, they may be read as octal) and masks.
  # The length limit also keeps `toInt` from overflowing or throwing.
  checkDecimal = val: typeOf val == "string" && match "0|[1-9][0-9]{0,2}" val != null;
  # RFC 4291 2.2.1: an IPv6 component has one to four hexadecimal digits
  checkHex = val: match "[0-9a-fA-F]{1,4}" val != null;

  # Splits an address with at most one "::" into its components, or returns null.
  # "::" stands for one or more zero components (RFC 4291 2.2.2). Empty components
  # outside of "::" (e.g. ":1:2:3:4:5:6:7" or "1:::2") are rejected. The number of
  # components is only checked here if "::" is present.
  ipGapSplit = meta: str:
    let
      pieces = splitString "${meta.componentSeparator}${meta.componentSeparator}" str;
      splitPiece = piece: if piece == "" then [ ] else splitString meta.componentSeparator piece;

      lstBeforeGap = splitPiece (head pieces);
      lstAfterGap = splitPiece (last pieces);
      fillerLength = meta.components - length lstBeforeGap - length lstAfterGap;
    in
    if length pieces == 1 then
      splitString meta.componentSeparator str
    else if length pieces > 2 || any (part: part == "") (lstBeforeGap ++ lstAfterGap) || fillerLength < 1 then
      null
    else
      lstBeforeGap ++ genList (i: "0") fillerLength ++ lstAfterGap;

  # Replaces a trailing dotted-quad IPv4 address in an IPv6 address by two hexadecimal
  # components (RFC 4291 2.2.3, e.g. "::ffff:192.0.2.1" -> "::ffff:c000:201"),
  # returns null if the IPv4 part is invalid.
  ip6EmbeddedIp4 = ip4: str:
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
      concatStringsSep ":" (init parts ++ [
        (hex (elemAt ip4Parts 0) (elemAt ip4Parts 1))
        (hex (elemAt ip4Parts 2) (elemAt ip4Parts 3))
      ]);

  ipGapJoin = meta: parts:
    let
      findGaps = foldl
        (acc: part:
          let
            currentGapOrNull = filter (x: x.end == part.index - 1) acc;
            currentGap = if length currentGapOrNull > 0 then head currentGapOrNull // { end = part.index; } else { start = part.index; end = part.index; };
          in
          if part.value == 0 then
            (filter (gap: gap.start != currentGap.start) acc) ++ [ currentGap ]
          else
            acc
        ) [ ]
        (map (x: { value = x.fst; index = x.snd; }) (lists.zipLists parts (genList (i: i) meta.components)));

      # RFC 5952 4.2.2: "::" must not shorten a single zero component
      compressibleGaps = filter (gap: gap.end > gap.start) findGaps;

      longestGap =
        if length compressibleGaps == 0 then
          null
        else
          foldl (acc: gap: if gap.end - gap.start > acc.end - acc.start then gap else acc) (head compressibleGaps) compressibleGaps;

      strParts = map meta.componentToString parts;

      lstBeforeGap =
        if longestGap.start == 0 then
          [ "" ]
        else
          lists.sublist 0 longestGap.start strParts;

      lstAfterGap =
        if longestGap.end == meta.components - 1 then
          [ "" ]
        else
          lists.sublist (longestGap.end + 1) meta.components strParts;

      strPartsRemovedGap =
        if longestGap == null then
          strParts
        else
          lstBeforeGap ++ [ "" ] ++ lstAfterGap;
    in
    concatStringsSep ":" strPartsRemovedGap;
in
rec {
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
    Int -> Int -> Number
    ```
  */
  pow = val: exp:
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
    `a` : An IP address
    `b`: An IP address

    # Output
    A string representing the relation of the two addresses:
    - "superset"
    - "equal"
    - "subset"
    - "disjoint"
    - `null` if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

    The output must be read as follows: "a" is <output> to/of "b".

    # Type
    ```nix
    String -> String -> String
    ```
    */
  subnetRelation' = address: network:
    let
      decomposedAddress = decompose' address;
      decomposedNetwork = decompose' network;

      validAddresses = decomposedNetwork != null && decomposedAddress != null &&
        decomposedNetwork._meta.name == decomposedAddress._meta.name;

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
      `a` : An IP address
      `b`: An IP address

      # Output
      A string representing the relation of the two addresses:
      - "superset"
      - "equal"
      - "subset"
      - "disjoint"

      The output must be read as follows: "a" is <output> to/of "b".

      # Errors
      Throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).
    */
  subnetRelation = address: network:
    let
      result = subnetRelation' address network;
    in
    if result != null then result else throw "Invalid IP addresses: ${toJSON address} and ${toJSON network}";

  /**
     Checks whether the given IP address is within the given subnet.

     Note that, this function accepts the ip address to have a larger network mask than
     the subnet, i.e. the address 1.2.3.4/24 is part of the subnet 1.2.0.0/16.
    If you want to check if the address is within the subnet and has the same network mask,
    use `subnetRelation'` instead.

    # Inputs
    `address` : An IP address that is maybe part of a network.
    `network`: An IP address representing a network.

    # Output
    A boolean indicating whether the address is within the subnet.

    # Type
    ```nix
    String -> String -> Bool
    ```
   */
  laysWithinSubnet' = address: network:
    let
      result = subnetRelation' address network;
    in
    if result == "equal" || result == "subset" then
      true
    else
      false;

  /**
      Checks whether the given IP address is within the given subnet.
      Same as `laysWithinSubnet'`, but throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

      # Inputs
      `address` : An IP address that is maybe part of a network.
      `network`: An IP address representing a network.

      # Output
      A boolean indicating whether the address is within the subnet.

      # Errors
      Throws an error if the input addresses are invalid or not of the same kind (IPv4 vs IPv6).

      # Type
      ```nix
      String -> String -> Bool
      ```
    */
  laysWithinSubnet = address: network:
    let
      result = subnetRelation' address network;
    in
    if result != null then (
      if result == "equal" || result == "subset" then
        true
      else
        false
    ) else throw "Invalid IP addresses: ${toJSON address} and ${toJSON network}";


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
  partsBitAnd = addressParts: maskParts:
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
  decompose' = address:
    let
      ipInterface = ip' address;
    in
    if ipInterface != null then
      ipInterface.decompose' address
    else
      null;


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
  decompose = address:
    let result = decompose' address;
    in if result != null then result else throw "Invalid IP address: ${toJSON address}";

  /**
    A function that calculates the n-th address in the given network.

    # Inputs
    `network` : An IP address representing a network in CIDR notation.
    `index` : An integer representing the index of the desired address within the network.

    # Output
    A string representing the n-th address in the given network, or `null` if the input is invalid or the index is out of range.

    # Type
    ```nix
    String -> Int -> String | null
    ```
  */
  assignAddress' = network: index:
    let
      ipInterface = ip' network;
      decomposed = ipInterface.decompose' network;
      networkParts = decomposed.networkParts;
      mask = decomposed.mask;

      addressParts = imap0
        (i: part:
          let
            reversedI = ipInterface.meta.components - 1 - i;
            availableBits = ipInterface.meta.componentBitWidth - (min ipInterface.meta.componentBitWidth (max 0 (mask - i * ipInterface.meta.componentBitWidth)));

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
          if data.offset >= pow 2 availableBits then
            null
          else
            bitOr part data.offset
        )
        networkParts;

      address = ipInterface.composeStr addressParts mask;

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
    A string representing the n-th address in the given network, or throws an error if the input is invalid or the index is out of range.

    # Type
    ```nix
    String -> Int -> String
    ```
  */
  assignAddress = network: index:
    let result = assignAddress' network index; in
    if result != null then result else throw "Invalid input or index out of range: ${toJSON network} with index ${toJSON index}";

  /**
    Reads `length` bits of the hex string `hex`, starting at bit `offset` (most
    significant bit first), as an integer.

    # Type
    ```nix
    String -> Int -> Int -> Int
    ```
    */
  hexBits = hex: offset: length: foldl
    (acc: bit:
      let
        position = offset + bit;
        nibble = trivial.fromHexString (substring (position / 4) 1 hex);
      in
      acc * 2 + (if bitAnd nibble (pow 2 (3 - mod position 4)) != 0 then 1 else 0))
    0
    (genList (bit: bit) length);

  /**
    Replaces the bits `from` (inclusive) to `to` (exclusive) of an address, given as
    its list of components, with the bits of the hex string `hex` (most significant bit
    first). Works per component, so any range of an IPv4 or IPv6 address can be set.

    # Type
    ```nix
    { meta : { ... }, parts : [ Int ], from : Int, to : Int, hex : String } -> [ Int ]
    ```
    */
  setBitsFromHex = { meta, parts, from, to, hex }: imap0
    (index: part:
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
        bitOr (bitAnd part (bitXor mask meta.componentMask)) (hexBits hex (low - from) length * pow 2 shift))
    parts;

  /**
    Derives a stable address for a device from its name, inside an IPv4 or IPv6 network,
    e.g. to address hosts, containers or VMs without keeping a list of hand-picked addresses.

    All bits the network leaves free (its device part) are taken from
    SHA-256(`salt` + ":address:" + `name`), so the same inputs always give the same address.

    Distinct names may get the same address, the likelihood increases with less device bits.
    Callers handing should assert that they are unique and usable (e.g. not a special address).

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
    { salt
    , network
    , name
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

    Distinct names may get the same subnet, the likelihood increases with less device bits.
    Callers handing should assert that they are unique/

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
    { salt
    , network
    , name
    , prefixLength
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
    A function that takes an IP address and returns the appropriate interface of functions to process it, or null if invalid.

    # Input
    `address` : An IP address, which can be either an IPv4 or IPv6 address.

    # Output
    The ip4 or ip6 interface depending on the type of the input IP address, or null if invalid.

    # Type
    ```nix
    String -> { ... } | null
    ```
    **/
  ip' = address:
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
    **/
  ip = address:
    let result = ip' address; in
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
    composeStr = addressParts: mask:
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
    calculateNetworkMaskParts = mask:
      if !checkIpMask mask then
        throw "Illegal arguments"
      else
        genList
          (i:
            let
              startOfComponent = i * meta.componentBitWidth;
              endOfComponent = startOfComponent + meta.componentBitWidth;
              bitsInComponent = max (min (mask - startOfComponent) meta.componentBitWidth) 0;
            in
            if mask <= startOfComponent then 0
            else if mask >= endOfComponent then meta.componentMask
            else (rep2Add bitsInComponent 1) * pow 2 (meta.componentBitWidth - bitsInComponent)
          )
          meta.components;

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
    calculateDeviceMaskParts = mask:
      map (part: bitAnd (bitNot part) meta.componentMask) (calculateNetworkMaskParts mask);

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
    decompose' = val:
      let
        validString = typeOf val == "string";

        parts = splitString "/" val;
        address = head parts;
        mask = if length parts > 1 then last parts else toString meta.bitWidth;
        validMask = length parts <= 2 && checkDecimal mask && toInt mask <= meta.bitWidth;

        chunkedAddress = meta.strToParts address;
        validAddressPart = chunkedAddress != null && length chunkedAddress == meta.components && all
          (part:
            let
              partInt = meta.componentFromString part;
            in
            meta.componentIsValidString part && partInt >= 0 && partInt <= meta.componentMask)
          chunkedAddress;

        chunks = map meta.componentFromString chunkedAddress;
        maskInt = toInt mask;
        networkMask = calculateNetworkMaskParts maskInt;
        deviceMask = calculateDeviceMaskParts maskInt;

        networkPart = partsBitAnd chunks networkMask;
        devicePart = partsBitAnd chunks deviceMask;

        compose = adr: composeStr adr maskInt;
        composeNoMask = adr: composeStr adr null;
      in
      if validString && validMask && validAddressPart then {
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
      } else null;

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
    decompose = val:
      let result = decompose' val; in
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
    checkIpParts = val: typeOf val == "list" && all (part: typeOf part == "int" && part >= 0 && part <= meta.componentMask) val && length val == meta.components;

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
    checkNormalizedNetwork = val:
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

    /** Checks if the given value is a valid IP address in CIDR notation without trailing /mask.

      # Input
      `val` : A string representing the IP address, e.g. "1.2.3.4".

      # Output
      A boolean indicating whether the input is a valid IP address without trailing /mask.

      # Type
      ```nix
      String -> Bool
      ```
      */
    checkNoMask = val:
      let
        result = decompose' val;
      in
      result != null && result.addressNoMask == val;

    /**
      Checks if the given value is a valid IP address in CIDR notation with trailing /mask.
  
      # Input
      `val` : A string representing the IP address in CIDR notation, e.g. "1.2.3.4/32"

      # Output
      A boolean indicating whether the input is a valid IP address in CIDR notation with trailing /mask.
      # Type
      ```nix
      String -> Bool
      ```
      */
    checkWithMask = val:
      let
        result = decompose' val;
      in
      result != null && result.address == val;

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
    partsToStr = addressParts: concatStringsSep componentSeparator (map componentToString addressParts); # Function to convert a list of components to a string representation
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
    strToParts = str: let str' = ip6EmbeddedIp4 ip4 str; in if str' == null then null else ipGapSplit ip6.meta str'; # Function to split a string representation of an IP address into its components
    partsToStr = ipGapJoin ip6.meta; # Function to convert a list of components to a string representation
  };

  types = import ./types.nix (inputs // {
    inherit ip4 ip6 partsBitAnd;
  });
}
