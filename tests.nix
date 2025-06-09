{ netLib, nixpkgs, lib ? nixpkgs.lib, ... }: {
  tests = with builtins; with lib; with netLib;
    let
      testCases = [
        {
          expression = pow 2 10;
          expected = 1024;
          description = "2^10 should be 1024";
        }

        {
          expression = ip4.composeStr [ 1 2 3 4 ] 24;
          expected = "1.2.3.4/24";
          description = "IP parts to string conversion";
        }
        {
          expression = ip4.calculateNetworkMaskParts 24;
          expected = [ 255 255 255 0 ];
          description = "IPv4 network mask for /24";
        }
        {
          expression = ip4.calculateNetworkMaskParts 13;
          expected = [ 255 248 0 0 ];
          description = "IPv4 device mask for /13";
        }
        {
          expression = ip4.calculateDeviceMaskParts 24;
          expected = [ 0 0 0 255 ];
          description = "IPv4 device mask for /24";
        }
        {
          expression = ip4.calculateDeviceMaskParts 13;
          expected = [ 0 7 255 255 ];
          description = "IPv4 device mask for /13";
        }
        {
          expression = ip4.decompose' "178.22.33.1/24";
          expected = {
            addressParts = [ 178 22 33 1 ];
            address = "178.22.33.1/24";
            addressNoMask = "178.22.33.1";
            networkParts = [ 178 22 33 0 ];
            network = "178.22.33.0/24";
            networkNoMask = "178.22.33.0";
            deviceParts = [ 0 0 0 1 ];
            device = "0.0.0.1/24";
            deviceNoMask = "0.0.0.1";
            networkMaskParts = [ 255 255 255 0 ];
            networkMask = "255.255.255.0/24";
            networkMaskNoMask = "255.255.255.0";
            mask = 24;
          };
          description = "Decomposing a valid IPv4 address";
        }
        {
          expression = ip4.decompose' "33--d";
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip4.decompose' 22;
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip4.decompose' { };
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip4.decompose' "178.22.33.1/13";
          expected = {
            addressParts = [ 178 22 33 1 ];
            address = "178.22.33.1/13";
            addressNoMask = "178.22.33.1";
            networkParts = [ 178 16 0 0 ];
            network = "178.16.0.0/13";
            networkNoMask = "178.16.0.0";
            deviceParts = [ 0 6 33 1 ];
            device = "0.6.33.1/13";
            deviceNoMask = "0.6.33.1";
            networkMaskParts = [ 255 248 0 0 ];
            networkMask = "255.248.0.0/13";
            networkMaskNoMask = "255.248.0.0";
            mask = 13;
          };
          description = "Decomposing a valid IPv4 address with /13 mask";
        }
        {
          expression = ip4.checkIpParts [ 178 22 33 1 ];
          expected = true;
          description = "Checking valid IPv4 parts";
        }
        {
          expression = ip4.checkIpParts [ 700 22 33 1 ];
          expected = false;
          description = "Checking invalid IPv4 parts";
        }
        {
          expression = ip4.checkIpParts [ 178 22 33 ];
          expected = false;
          description = "Checking incomplete IPv4 parts";
        }
        {
          expression = ip4.checkIpParts [ 178 22 33 2 3 ];
          expected = false;
          description = "Checking invalid IPv4 parts";
        }
        {
          expression = ip4.checkIpMask 24;
          expected = true;
          description = "Checking valid IPv4 mask";
        }
        {
          expression = ip4.checkIpMask 32;
          expected = true;
          description = "Checking valid IPv4 mask";
        }
        {
          expression = ip4.checkIpMask 33;
          expected = false;
          description = "Checking invalid IPv4 mask";
        }
        {
          expression = ip4.checkIpMask (-1);
          expected = false;
          description = "Checking negative IPv4 mask";
        }

        {
          expression = ip6.composeStr [ 1 2 3 4 5 6 7 8 ] 24;
          expected = "1:2:3:4:5:6:7:8/24";
          description = "IP parts to string conversion";
        }
        {
          expression = ip6.composeStr [ 1 0 0 4 0 0 0 8 ] 24;
          expected = "1:0:0:4::8/24";
          description = "IP parts to string conversion";
        }
        {
          expression = ip6.composeStr [ 0 0 0 4 0 0 0 8 ] 24;
          expected = "::4:0:0:0:8/24";
          description = "IP parts to string conversion";
        }
        {
          expression = ip6.composeStr [ 1 0 0 0 0 0 0 0 ] 24;
          expected = "1::/24";
          description = "IP parts to string conversion";
        }
        {
          expression = ip6.calculateNetworkMaskParts 24;
          expected = [ 65535 65280 0 0 0 0 0 0 ];
          description = "IPv4 network mask for /24";
        }
        {
          expression = ip6.calculateNetworkMaskParts 13;
          expected = [ 65528 0 0 0 0 0 0 0 ];
          description = "IPv4 device mask for /13";
        }
        {
          expression = ip6.calculateDeviceMaskParts 24;
          expected = [ 0 255 65535 65535 65535 65535 65535 65535 ];
          description = "IPv4 device mask for /24";
        }
        {
          expression = ip6.calculateDeviceMaskParts 13;
          expected = [ 7 65535 65535 65535 65535 65535 65535 65535 ];
          description = "IPv4 device mask for /13";
        }
        {
          expression = ip6.decompose' "fe80:2:3:4::1/64";
          expected = {
            addressParts = [ 65152 2 3 4 0 0 0 1 ];
            address = "fe80:2:3:4::1/64";
            addressNoMask = "fe80:2:3:4::1";
            networkParts = [ 65152 2 3 4 0 0 0 0 ];
            network = "fe80:2:3:4::/64";
            networkNoMask = "fe80:2:3:4::";
            deviceParts = [ 0 0 0 0 0 0 0 1 ];
            device = "::1/64";
            deviceNoMask = "::1";
            networkMaskParts = [ 65535 65535 65535 65535 0 0 0 0 ];
            networkMask = "ffff:ffff:ffff:ffff::/64";
            networkMaskNoMask = "ffff:ffff:ffff:ffff::";
            mask = 64;
          };
          description = "Decomposing a valid IPv4 address";
        }
        {
          expression = ip6.decompose' "33--d";
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip6.decompose' "1::2::4/64";
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip6.decompose' 22;
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip6.decompose' { };
          expected = null;
          description = "Invalid IP address should return null";
        }
        {
          expression = ip6.checkIpParts [ 1 2 3 4 5 6 7 8 ];
          expected = true;
          description = "Checking valid IPv6 parts";
        }
        {
          expression = ip6.checkIpParts [ 70000 2 3 4 5 6 7 8 ];
          expected = false;
          description = "Checking invalid IPv6 parts";
        }
        {
          expression = ip6.checkIpParts [ 1 2 3 4 5 6 7 ];
          expected = false;
          description = "Checking incomplete IPv6 parts";
        }
        {
          expression = ip6.checkIpParts [ 1 2 3 4 5 6 7 8 9 ];
          expected = false;
          description = "Checking invalid IPv6 parts";
        }
        {
          expression = ip6.checkIpMask 64;
          expected = true;
          description = "Checking valid IPv6 mask";
        }
        {
          expression = ip6.checkIpMask 128;
          expected = true;
          description = "Checking valid IPv6 mask";
        }
        {
          expression = ip6.checkIpMask 129;
          expected = false;
          description = "Checking invalid IPv6 mask";
        }
        {
          expression = ip6.checkIpMask (-1);
          expected = false;
          description = "Checking negative IPv6 mask";
        }

        {
          expression = subnetRelation' "1.2.3.4/24" "fe80::1/64";
          expected = null;
          description = "Subnet relation between IPv4 and IPv6 should return null";
        }
        {
          expression = subnetRelation' "1.2.3.4/24" "1.2.3.88/24";
          expected = "equal";
          description = "Subnet relation between two IPv4 addresses should return equal";
        }
        {
          expression = subnetRelation' "1.2.3.4/24" "1.2.88.19/12";
          expected = "subset";
          description = "Subnet relation between two IPv4 addresses should return subset";
        }
        {
          expression = subnetRelation' "1.2.88.19/12" "1.2.3.4/24";
          expected = "superset";
          description = "Subnet relation between two IPv4 addresses should return superset";
        }
      ];
    in
    foldl
      (acc: testCase:
        let
          expression = testCase.expression;
          expected = testCase.expected;
          description = testCase.description;

          allEqual = list: all (x: x == head list) list;

          zipped = attrsets.zipAttrs [ expression expected ];
          onlyDifference = attrsets.filterAttrs (k: v: (!(allEqual v) || length v != 2) && (head (strings.stringToCharacters k) != "_")) zipped;

          differenceSet = attrNames onlyDifference;

          mismatchString =
            if typeOf expected == "string" then
              "Expected ${toJSON expected}, got ${toJSON expression}."
            else if typeOf expected == "set" then
              "Difference in attributes: ${toJSON onlyDifference}."
            else
              "Expected ${toJSON expected}, got ${toJSON expression}.";
        in
        if expression == expected || (typeOf expected == "set" && length differenceSet == 0) then
          acc + 1
        else
          throw "Test ${toString (acc+1)} failed: '${description}'. ${mismatchString}."
      ) 0
      testCases;
}
