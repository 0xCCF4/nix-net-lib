{
  description = "Nix library for parsing and manipulating IP addresses";

  inputs = {
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  };

  outputs =
    { self
    , nixpkgs-lib
    , ...
    }:
    let
      lib = nixpkgs-lib.lib;

      netLib = import ./lib.nix { inherit lib; };

      # Number of test cases, throws listing all failures otherwise
      tests = (import ./tests.nix {
        inherit lib netLib;
      }).tests;

      libOverlay = import ./lib-overlay.nix { inherit netLib; };

      overlays = import ./overlays.nix { inherit libOverlay; };

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      # Expose library via `nix-net-lib.lib`
      lib = netLib;

      # Run via `nix eval .#tests`
      inherit tests;

      # Overlay for the nixpkgs library: `nixpkgs.lib.extend libOverlay`
      inherit libOverlay;

      # Expose nixpkgs overlays
      overlays.default = overlays;

      # Makes the library available as the `netLib` module argument
      nixosModules.default = { _module.args.netLib = netLib; };

      # `nix flake check` only evaluates (and builds) this if all tests pass
      checks = lib.genAttrs systems (system: {
        tests = builtins.derivation {
          name = "netlib-tests";
          inherit system;
          builder = "/bin/sh";
          args = [ "-c" "echo '${toString tests} tests passed' > $out" ];
        };
      });
    };
}
