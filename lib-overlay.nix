# Overlay for the nixpkgs library, adds this library as `lib.net` and its option types as
# `lib.types.net`. Use with `nixpkgs.lib.extend`:
#   lib = nixpkgs.lib.extend netlib.libOverlay;
{ netLib
, ...
}: final: prev: {
  net = (
    # Maybe nixpkgs will eventually have a .net namespace
    # in that case extend it instead of overriding
    prev.net or { }
  ) // netLib;

  types = prev.types // {
    net = (
      # Maybe nixpkgs will eventually have a .types.net namespace
      # in that case extend it instead of overriding
      prev.types.net or { }
    ) // netLib.types;
  };
}
