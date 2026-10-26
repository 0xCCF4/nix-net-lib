# Overlay for nixpkgs, extends `pkgs.lib` with `lib.net` and `lib.types.net`,
# see lib-overlay.nix.
{ netLib ? null
, libOverlay ? import ./lib-overlay.nix { inherit netLib; }
, ...
}: final: prev: {
  lib = prev.lib.extend libOverlay;
}
