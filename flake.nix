{
  description = "A basic shell for ArDrive-Web";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            ruby
            cocoapods
            fastlane
            nodejs
            yarn-berry
            nodePackages.typescript-language-server
          ];
          shellHook = ''
            export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
            echo "Welcome to ArDrive-Web shell"
          '';
        };
      });
}
