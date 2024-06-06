{
  nixConfig.extra-substituters = [
    "https://nixsgx.cachix.org"
  ];
  nixConfig.extra-trusted-public-keys = [
    "nixsgx.cachix.org-1:tGi36DlY2joNsIXOlGnSgWW0+E094V6hW0umQRo/KoE="
  ];

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  description = "SGX packages for nixos";

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;

      package-namespace = "nixsgx";

      snowfall = {
        namespace = "nixsgx";
      };

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixpkgs-fmt;
      };
    };
}
