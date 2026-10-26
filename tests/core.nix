# Core test cases (parsing, rendering, subnet math, hashing). See ../tests.nix for the format.
{ lib, netLib, throws, ... }: with builtins; with lib; with netLib; [
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
    expression = ip6.decompose' "fe80::/64";
    expected = {
      addressParts = [ 65152 0 0 0 0 0 0 0 ];
      address = "fe80::/64";
      addressNoMask = "fe80::";
      networkParts = [ 65152 0 0 0 0 0 0 0 ];
      network = "fe80::/64";
      networkNoMask = "fe80::";
      deviceParts = [ 0 0 0 0 0 0 0 0 ];
      device = "::/64";
      deviceNoMask = "::";
      networkMaskParts = [ 65535 65535 65535 65535 0 0 0 0 ];
      networkMask = "ffff:ffff:ffff:ffff::/64";
      networkMaskNoMask = "ffff:ffff:ffff:ffff::";
      mask = 64;
    };
    description = "Decomposing a valid IPv6 address with trailing ::";
  }
  {
    expression = ip6.decompose' "::1/128";
    expected = {
      addressParts = [ 0 0 0 0 0 0 0 1 ];
      address = "::1/128";
      addressNoMask = "::1";
      networkParts = [ 0 0 0 0 0 0 0 1 ];
      network = "::1/128";
      networkNoMask = "::1";
      deviceParts = [ 0 0 0 0 0 0 0 0 ];
      device = "::/128";
      deviceNoMask = "::";
      networkMaskParts = [ 65535 65535 65535 65535 65535 65535 65535 65535 ];
      networkMask = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128";
      networkMaskNoMask = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      mask = 128;
    };
    description = "Decomposing a valid IPv6 address with leading ::";
  }
  {
    expression = ip6.decompose' "::/64";
    expected = {
      addressParts = [ 0 0 0 0 0 0 0 0 ];
      address = "::/64";
      addressNoMask = "::";
      networkParts = [ 0 0 0 0 0 0 0 0 ];
      network = "::/64";
      networkNoMask = "::";
      deviceParts = [ 0 0 0 0 0 0 0 0 ];
      device = "::/64";
      deviceNoMask = "::";
      networkMaskParts = [ 65535 65535 65535 65535 0 0 0 0 ];
      networkMask = "ffff:ffff:ffff:ffff::/64";
      networkMaskNoMask = "ffff:ffff:ffff:ffff::";
      mask = 64;
    };
    description = "Decomposing a valid IPv6 address of all zeros";
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

  {
    expression = assignAddress' "fe80::/64" 2;
    expected = "fe80::2";
    description = "Check if ip6 assignAddress works (returns the address without mask)";
  }
  {
    expression = assignAddress' "1.1.1.0/24" 0;
    expected = "1.1.1.0";
    description = "Calculate the zero-th address in the subnet";
  }
  {
    expression = assignAddress' "1.1.1.55/24" 0;
    expected = "1.1.1.0";
    description = "Calculate the zero-th address in the subnet";
  }
  {
    expression = assignAddress' "1.1.1.0/24" 2;
    expected = "1.1.1.2";
    description = "Calculate the n-th address in the subnet";
  }
  {
    expression = assignAddress' "1.1.1.0/24" 6;
    expected = "1.1.1.6";
    description = "Calculate the n-th address in the subnet";
  }
  {
    expression = assignAddress' "1.1.1.0/24" 400;
    expected = null;
    description = "Calculate the n-th address in the subnet, out-of-bounds";
  }
  {
    expression = assignAddress' "1.1.1.128/25" 2;
    expected = "1.1.1.130";
    description = "Calculate the n-th address in the subnet";
  }
  {
    expression = assignAddress' "1.1.0.0/16" 256;
    expected = "1.1.1.0";
    description = "Calculate the n-th address in the subnet overflowing octet";
  }

  {
    expression = assignAddress' "1.1.0.0/16" 258;
    expected = "1.1.1.2";
    description = "Calculate the n-th address in the subnet overflowing octet";
  }
  {
    expression = ip6.composeStr [ 8193 3512 0 1 1 1 1 1 ] null;
    expected = "2001:db8:0:1:1:1:1:1";
    description = "A single zero component is not shortened to :: (RFC 5952 4.2.2)";
  }
  {
    expression = hashedAddress { salt = "s"; network = "2001:db8::/64"; name = "host-a"; };
    expected = "2001:db8::f0a3:42e6:b7cf:1582";
    description = "Check if hashedAddress fills the device part of an IPv6 /64";
  }
  {
    expression = hashedAddress { salt = "s"; network = "2001:db8::/50"; name = "host-a"; };
    expected = "2001:db8:0:3c28:d0b9:adf3:c560:bae9";
    description = "Check if hashedAddress works for masks that are no multiple of 16";
  }
  {
    expression = hashedAddress { salt = "s"; network = "198.51.100.0/22"; name = "host-a"; };
    expected = "198.51.103.194";
    description = "Check if hashedAddress works for IPv4";
  }
  {
    expression = hashedSubnet { salt = "s"; network = "fd12:3456:789a::/48"; name = "office"; prefixLength = 64; };
    expected = "fd12:3456:789a:894d::/64";
    description = "Check if hashedSubnet works for a /64 out of a /48";
  }
  {
    expression = hashedSubnet { salt = "s"; network = "fd12:3456:789a::/48"; name = "office"; prefixLength = 57; };
    expected = "fd12:3456:789a:8900::/57";
    description = "Check if hashedSubnet works for prefix lengths that are no multiple of 16";
  }
  {
    expression = hashedSubnet { salt = "s"; network = "10.0.0.0/8"; name = "office"; prefixLength = 20; };
    expected = "10.137.64.0/20";
    description = "Check if hashedSubnet works for IPv4";
  }
  {
    expression = map ip6.check [ "00001::" "02001:db8::1" ];
    expected = [ false false ];
    description = "IPv6 components have at most four hex digits (RFC 4291 2.2.1)";
  }
  {
    expression = ip6.check "ffffffffffffffffff::";
    expected = false;
    description = "Overlong IPv6 components are rejected instead of overflowing (RFC 4291 2.2.1)";
  }
  {
    expression = map ip6.check [ "1:::2" ":1:2:3:4:5:6:7" "1:2:3:4:5:6:7:" ":::" ];
    expected = [ false false false false ];
    description = "Empty IPv6 components outside of :: are rejected (RFC 4291 2.2.2)";
  }
  {
    expression = ip6.check "1:2:3:4::5:6:7:8";
    expected = false;
    description = ":: stands for at least one zero component, so at most seven others are allowed (RFC 4291 2.2.2)";
  }
  {
    expression = (ip6.decompose "1:2:3:4:5:6:7::").addressNoMask;
    expected = "1:2:3:4:5:6:7:0";
    description = ":: may stand for a single zero component on input (RFC 4291 2.2.2), but is not emitted for it (RFC 5952 4.2.2)";
  }
  {
    expression = map ip6.check [ "1:2:3" "1:2:3:4:5:6:7:8:9" ];
    expected = [ false false ];
    description = "IPv6 addresses without :: have exactly eight components (RFC 4291 2.2.1)";
  }
  {
    expression = map ip4.check [ "1.2.3" "1.2.3.4.5" ];
    expected = [ false false ];
    description = "IPv4 addresses have exactly four octets (RFC 791 / RFC 6943 3.1.1)";
  }
  {
    expression = map ip4.check [ "01.2.3.4" "1.2.3.04" "999999999999999999999.1.1.1" ];
    expected = [ false false false ];
    description = "IPv4 octets with leading zeros (ambiguous octal, RFC 6943 3.1.1) or overflowing values are rejected instead of throwing";
  }
  {
    expression = map ip4.check [ "1.2.3.4/0" "1.2.3.4/32" "1.2.3.4/33" "1.2.3.4/100" "1.2.3.4/024" "1.2.3.4/99999999999999999999" ];
    expected = [ true true false false false false ];
    description = "IPv4 prefix lengths are 0 to 32 (RFC 4632 3.1), malformed ones are rejected instead of throwing";
  }
  {
    expression = map ip6.check [ "::/0" "::/128" "::/129" "::/1024" ];
    expected = [ true true false false ];
    description = "IPv6 prefix lengths are 0 to 128 (RFC 4291 2.3)";
  }
  {
    expression = map (s: (ip6.decompose s).address) [ "::ffff:192.0.2.1" "64:ff9b::192.0.2.1/96" "1:2:3:4:5:6:1.2.3.4" ];
    expected = [ "::ffff:192.0.2.1/128" "64:ff9b::c000:201/96" "1:2:3:4:5:6:102:304/128" ];
    description = "IPv6 addresses with an embedded dotted-quad IPv4 address are accepted (RFC 4291 2.2.3)";
  }
  {
    expression = map ip6.check [ "::ffff:01.2.3.4" "::ffff:1.2.3" "::1.2.3.4:5" "1:2:3:4:5:6:7:1.2.3.4" ];
    expected = [ false false false false ];
    description = "An embedded IPv4 address must be a valid dotted quad in the last 32 bits (RFC 4291 2.2.3)";
  }
  {
    expression = map (assignAddress' "1.2.3.0/24") [ (-1) ];
    expected = [ null ];
    description = "assignAddress rejects negative indices";
  }
  {
    expression = map (assignAddress' "0.0.0.0/0") [ 4294967295 4294967296 ];
    expected = [ "255.255.255.255" null ];
    description = "assignAddress rejects indices beyond the address length instead of wrapping around";
  }
  {
    expression = map (assignAddress' "1.2.3.4/31") [ 0 1 2 ];
    expected = [ "1.2.3.4" "1.2.3.5" null ];
    description = "assignAddress in an IPv4 /31 (RFC 3021)";
  }

  # Parser robustness: check/decompose' return false/null for any input, never throw
  {
    expression =
      let
        inputs = [
          "" "/" ":" ":::" "::::" "." "..." "1.2.3.4/" "/24" "1.2.3.4//24" "1.2.3.4/24/24"
          "1..2.3" "1.2.3.4." ".1.2.3.4" "a.b.c.d" "-1.2.3.4" "1.2.3.4/-1" "1.2.3.4/ 24" " 1.2.3.4"
          "1.2.3.4.5" "1.2.3" "01.2.3.4" "00.0.0.0" "123456.1.1.1" "99999999999999999999999.1.1.1"
          "1.2.3.4/33" "1.2.3.4/0033" "1:2:3" "1:2:3:4:5:6:7:8:9" "1:2:3:4::5:6:7:8" "1::2::3"
          "1:2:3:4:5:6:7::8" "::1:2:3:4:5:6:7:8" "g::1" "12345::" "::/129" "::/" "fe80::1%eth0"
          "::ffff:1.2.3.4.5" "::ffff:256.1.1.1" "::ffff:1.2.3" "1.2.3.4::" "::1.2.3.4:5" "::ffff:01.2.3.4"
          "1:2:3:4:5:6:7:1.2.3.4" "::1.2.3.4/129" "\n" "1.2.3.4\n"
        ];
        nonStrings = [ null 22 1.5 true [ ] { } [ "1.2.3.4" ] (x: x) ./. ];
        safe = f: x: let r = tryEval (deepSeq (f x) (f x)); in r.success && (r.value == false || r.value == null);
      in
      filter
        (x: !(all (f: safe f x) [ ip4.check ip6.check ip4.decompose' ip6.decompose' decompose' canonical' ip4.checkNoMask ip6.checkWithMask ip6.checkCanonical ]))
        (inputs ++ nonStrings);
    expected = [ ];
    description = "check/decompose'/canonical' return false/null instead of throwing for invalid strings and non-strings";
  }
  {
    expression = map (s: throws (ip4.decompose s)) [ "1.2.3.4/33" "01.2.3.4" "1.2.3.4.5" "1.2.3.4" ];
    expected = [ true true true false ];
    description = "decompose throws (with a catchable error) on invalid input";
  }
  {
    expression = map ip6.check [ "::" "1::" "::1" "::1:2:3:4:5:6:7" "1:2:3:4:5:6:7::" "1:2:3::4:5:6:7" "FE80::A" ];
    expected = [ true true true true true true true ];
    description = "Valid uses of :: and upper case hex digits are accepted";
  }
  {
    expression = map ip6.check [ "1:2:3:4:5:6:7::8" "::1:2:3:4:5:6:7:8" "1::2::3" "::::" "g::1" "12345::" ];
    expected = [ false false false false false false ];
    description = ":: must stand for at least one zero component, components are 1-4 hex digits";
  }
  {
    expression = map ip4.check [ "0.0.0.0" "255.255.255.255" "256.0.0.0" "00.0.0.0" "123456.1.1.1" "1.2.3.4/032" ];
    expected = [ true true false false false false ];
    description = "IPv4 octets and masks are decimal without leading zeros and in range";
  }
  {
    expression = ip6.composeStr [ 1 0 0 2 0 0 3 4 ] null;
    expected = "1::2:0:0:3:4";
    description = "The first of two equally long zero runs is shortened (RFC 5952 4.2.3)";
  }

  # Embedded / IPv4-mapped IPv6 addresses
  {
    expression = map canonical' [ "::ffff:1.2.3.4" "::FFFF:1.2.3.4" "::ffff:102:304" "0:0:0:0:0:ffff:1.2.3.4/120" "::ffff:0:0/96" ];
    expected = [ "::ffff:1.2.3.4" "::ffff:1.2.3.4" "::ffff:1.2.3.4" "::ffff:1.2.3.4/120" "::ffff:0.0.0.0/96" ];
    description = "IPv4-mapped addresses are rendered as ::ffff:a.b.c.d (RFC 5952 5)";
  }
  {
    expression = map canonical' [ "64:ff9b::192.0.2.1" "::1.2.3.4" "::ffff:0:1.2.3.4" "1::ffff:1.2.3.4" ];
    expected = [ "64:ff9b::c000:201" "::102:304" "::ffff:0:102:304" "1::ffff:102:304" ];
    description = "Other addresses with an embedded IPv4 address are rendered in hex (RFC 5952 5)";
  }
  {
    expression = (ip6.decompose "::ffff:1.2.3.4/96").addressParts;
    expected = [ 0 0 0 0 0 65535 258 772 ];
    description = "An embedded IPv4 address counts as the last two components";
  }
  {
    expression = map (s: ip6.checkCanonical s) [ "::ffff:1.2.3.4" "::ffff:102:304" ];
    expected = [ true false ];
    description = "The canonical spelling of an IPv4-mapped address is the dotted one";
  }

  # checkNoMask / checkWithMask / checkCanonical / canonical
  {
    expression = map ip6.checkNoMask [ "2001:DB8::1" "2001:db8:0:0::1" "2001:db8::1" "2001:db8::1/64" "foo" 22 ];
    expected = [ true true true false false false ];
    description = "checkNoMask accepts any valid spelling without /mask";
  }
  {
    expression = map ip6.checkWithMask [ "2001:DB8::1/64" "2001:db8::1/64" "2001:db8::1" "2001:db8::1/129" null ];
    expected = [ true true false false false ];
    description = "checkWithMask accepts any valid spelling with /mask";
  }
  {
    expression = map ip4.checkNoMask [ "1.2.3.4" "1.2.3.4/32" ];
    expected = [ true false ];
    description = "ip4 checkNoMask";
  }
  {
    expression = map ip6.checkCanonical [ "2001:db8::1" "2001:db8::1/64" "2001:db8::/64" "2001:DB8::1" "2001:db8:0::1" "2001:db8::1/064" 22 ];
    expected = [ true true true false false false false ];
    description = "checkCanonical only accepts the RFC 5952 spelling";
  }
  {
    expression = map ip4.checkCanonical [ "1.2.3.4" "1.2.3.4/24" "1.2.3.4/32" ];
    expected = [ true true true ];
    description = "ip4 checkCanonical";
  }
  {
    expression = map canonical' [ "2001:DB8:0:0::1/64" "2001:DB8:0:0::1" "1.2.3.4" "1.2.3.4/24" "::0:1" "foo" null ];
    expected = [ "2001:db8::1/64" "2001:db8::1" "1.2.3.4" "1.2.3.4/24" "::1" null null ];
    description = "canonical' keeps the /mask iff the input has one and keeps the device part";
  }
  {
    expression = [ (canonical "FE80::1") (throws (canonical "foo")) (throws (canonical 22)) ];
    expected = [ "fe80::1" true true ];
    description = "canonical throws on invalid input";
  }
  {
    expression = map types.ip6NoMask.check [ "2001:DB8::1" "2001:db8::1/64" ];
    expected = [ true false ];
    description = "types.ip6NoMask accepts any valid spelling without /mask";
  }

  # assignAddress returns the address without mask
  {
    expression = [ (assignAddress "2001:db8::/64" 1) (assignAddress "10.0.0.0/8" 65536) (throws (assignAddress "10.0.0.0/24" 256)) (throws (assignAddress "foo" 1)) ];
    expected = [ "2001:db8::1" "10.1.0.0" true true ];
    description = "assignAddress returns the address without mask and throws on invalid input";
  }

  # Library overlay
  {
    expression =
      let
        extended = lib.extend (import ../lib-overlay.nix { inherit netLib; });
      in
      [ (extended.net.ip4.check "1.2.3.4") (extended.types.net.ip4.check "1.2.3.4") (extended.types ? str) ];
    expected = [ true true true ];
    description = "libOverlay adds lib.net and lib.types.net";
  }
]
