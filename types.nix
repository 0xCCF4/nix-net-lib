{ nixpkgs ? import <nixpkgs> { }
, lib ? nixpkgs.lib
, ip4
, ip6
, partsBitAnd
, ...
}: with lib; with lib.types;
let
  ipType = interface: mkOptionType {
    name = interface.meta.name;
    description = interface.meta.description;
    descriptionClass = "noun";
    check = interface.check;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  ipNoMaskType = interface: mkOptionType {
    name = "${interface.meta.name}NoMask";
    description = "${interface.meta.description}, without trailing /mask";
    descriptionClass = "nonRestrictiveClause";
    check = interface.checkNoMask;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  ipExplicitMaskType = interface: mkOptionType {
    name = "${interface.meta.name}ExplicitMask";
    description = "${interface.meta.description}, with explicit /mask set";
    descriptionClass = "nonRestrictiveClause";
    check = interface.checkWithMask;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  ipNetworkType = mkOptionType {
    name = "${interface.meta.name}Network";
    description = "${interface.meta.description}, normalized network address";
    descriptionClass = "nonRestrictiveClause";
    check = interface.checkNormalizedNetwork;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  # withinNetworkStrictType = interface: networkAddress:
  #   let
  #     normalizedAddress = (decompose networkAddress).network;
  #   in
  #   {
  #     name = "${interface.meta.name}WithinNetworkStrict-${normalizedAddress}";
  #     description = "${interface.meta.description}, within subnet ${normalizedAddress} and masks are equal";
  #     descriptionClass = "nonRestrictiveClause";
  #     check = value:
  #       let
  #         decomposedValue = interface.decompose' value;
  #         decomposedNetwork = interface.decompose' networkAddress;
  #         relation = interface.subnetRelation decomposedValue decomposedNetwork;
  #       in
  #       validAddresses && masksEqual && relation == "equal";
  #   };
  # 
  # withinNetworkType = interface: networkAddress:
  #   let
  #     normalizedAddress = (decompose networkAddress).network;
  #   in
  #   {
  #     name = "${interface.meta.name}WithinNetwork-${normalizedAddress}";
  #     description = "${interface.meta.description}, within subnet ${normalizedAddress} and masks are equal";
  #     descriptionClass = "nonRestrictiveClause";
  #     check = value:
  #       let
  #         decomposedValue = interface.decompose' value;
  #         decomposedNetwork = interface.decompose' networkAddress;
  #         relation = interface.subnetRelation decomposedValue decomposedNetwork;
  #       in
  #       validAddresses && masksEqual && (relation == "subset" || relation == "equal");
  #   };
in
rec
{
  ip = oneOf [ (ipType ip4) (ipType ip6) ];
  ip4 = ipType ip4;
  ip6 = ipType ip6;

  ipNetwork = oneOf [ (ipNetworkType ip4) (ipNetworkType ip6) ];
  ip4Network = ipNetworkType ip4;
  ip6Network = ipNetworkType ip6;

  # ip4WithinNetworkStrict = withinNetworkStrict ip4;
  # ip6WithinNetworkStrict = withinNetworkStrict ip6;
  # 
  # ip4WithinNetwork = withinNetwork ip4;
  # ip6WithinNetwork = withinNetwork ip6;

  ipNoMask = oneOf [ (ipNoMaskType ip4) (ipNoMaskType ip6) ];
  ip4NoMask = ipNoMaskType ip4;
  ip6NoMask = ipNoMaskType ip6;

  ipExplicitMask = oneOf [ (ipExplicitMaskType ip4) (ipExplicitMaskType ip6) ];
  ip4ExplicitMask = ipExplicitMaskType ip4;
  ip6ExplicitMask = ipExplicitMaskType ip6;
}
