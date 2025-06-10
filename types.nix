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

  ipNoMask = interface: mkOptionType {
    name = "${interface.meta.name}NoMask";
    description = "${interface.meta.description}, without trailing /mask";
    descriptionClass = "nonRestrictiveClause";
    check = interface.checkNoMask;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  ipExplicitMask = interface: mkOptionType {
    name = "${interface.meta.name}ExplicitMask";
    description = "${interface.meta.description}, with explicit /mask set";
    descriptionClass = "nonRestrictiveClause";
    check = interface.checkWithMask;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  ipNetwork = mkOptionType {
    name = "${interface.meta.name}Network";
    description = "${interface.meta.description}, normalized network address";
    descriptionClass = "nonRestrictiveClause";
    check = interface.checkNormalizedNetwork;
    merge = loc: defs: mergeEqualOption loc (map normalize defs);
  };

  # withinNetworkStrict = interface: networkAddress:
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
  # withinNetwork = interface: networkAddress:
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

  ipNetwork = oneOf [ (ipNetwork ip4) (ipNetwork ip6) ];
  ip4Network = ipNetwork ip4;
  ip6Network = ipNetwork ip6;

  # ip4WithinNetworkStrict = withinNetworkStrict ip4;
  # ip6WithinNetworkStrict = withinNetworkStrict ip6;
  # 
  # ip4WithinNetwork = withinNetwork ip4;
  # ip6WithinNetwork = withinNetwork ip6;

  ipNoMask = oneOf [ (ipNoMask ip4) (ipNoMask ip6) ];
  ip4NoMask = ipNoMask ip4;
  ip6NoMask = ipNoMask ip6;

  ipExplicitMask = oneOf [ (ipExplicitMask ip4) (ipExplicitMask ip6) ];
  ip4ExplicitMask = ipExplicitMask ip4;
  ip6ExplicitMask = ipExplicitMask ip6;
}
