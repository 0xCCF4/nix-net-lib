{ nixpkgs
, netLib
, lib ? nixpkgs.lib
, ...
}: final: prev: {
  # Augment nix library with .net namespace
  lib = prev.lib // {
    net = (
      # Maybe nixpkgs will eventually have a .net namespace
      # in that case extend it instead of overriding
      prev.lib.net or { }
    ) // netLib;

    types = prev.lib.types // {
      net = (
        # Maybe nixpkgs will eventually have a .types.net namespace
        # in that case extend it instead of overriding
        prev.lib.types.net or { }
      ) // netLib.types;
    };
  };
}
