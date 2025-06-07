{
  description = "Nix library for parsing and manipulating IP addresses";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self
    , nixpkgs
    , ...
    }: let
        lib = import ./lib.nix { inherit nixpkgs; };
        tests = (import ./tests.nix {
            inherit nixpkgs;
            netLib = lib;
        }).tests > 0;

        overlays = import ./overlays.nix {
          inherit nixpkgs;
          netLib = lib;
        };
    in
      assert tests; {
        # Expose library via `nix-ip-types.lib`
        inherit lib;

        # Expose nixpkgs overlays
        overlays.default = overlays;
      };
}
