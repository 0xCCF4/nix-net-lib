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

  checkInt = val:
    if typeOf val == "int" then
      true
    else if typeOf val == "string" then
      match "[0-9]+" val != null
    else
      false;
  checkHex = val: match "^[0-9a-fA-F]+$" val != null;

  ipGapSplit = meta: str:
    let
      parts = splitString meta.componentSeparator str;
      indexedParts = lists.zipLists parts (genList (i: i) (length parts));
      gaps = filter (part: part.fst == "") indexedParts;

      gapIndex = (head gaps).snd;

      lstBeforeGap = lists.sublist 0 gapIndex parts;
      lstAfterGap = lists.sublist (gapIndex + 1) (length parts) parts;
      lstFiller = genList (i: "0") (meta.components - length parts + 1);
    in
    if length gaps > 1 then
      null
    else if length gaps == 0 then
      parts
    else
      lstBeforeGap ++ lstFiller ++ lstAfterGap;

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

      longestGap =
        if length findGaps == 0 then
          null
        else
          foldl (acc: gap: if gap.end - gap.start > acc.end - acc.start then gap else acc) (head findGaps) findGaps;

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
    if result != null then result else throw "Invalid IP addresses: ${toString address} and ${toString network}";

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
      result = laysWithinSubnet' address network;
    in
    if result != null then result else throw "Invalid IP addresses: ${toString address} and ${toString network}";


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
    in if result != null then result else throw "Invalid IP address: ${toString address}";

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
    if result != null then result else throw "Invalid IP address: ${toString address}";

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
        validMask = length parts <= 2 && checkInt mask && toInt mask >= 0 && toInt mask <= meta.bitWidth;

        chunkedAddress = meta.strToParts address;
        validAddressPart = chunkedAddress != null && all
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
      if (validString && validMask && validAddressPart) then {
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
      if result != null then result else throw "Invalid ${meta.description}: ${toString val}";

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
    componentIsValidString = checkInt; # Function to check if a string is a valid component
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
    strToParts = ipGapSplit ip6.meta; # Function to split a string representation of an IP address into its components
    partsToStr = ipGapJoin ip6.meta; # Function to convert a list of components to a string representation
  };

  types = import ./types.nix (inputs // {
    inherit ip4 ip6 partsBitAnd;
  });
}
