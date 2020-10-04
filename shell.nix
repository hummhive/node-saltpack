{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    buildInputs = [
     pkgs.nodejs-14_x

     # for npm sodium
     pkgs.libsodium
     pkgs.libtool
     pkgs.autoconf
     pkgs.automake
     pkgs.nodePackages.node-gyp
    ];
}
