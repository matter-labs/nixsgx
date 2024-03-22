args@{ callPackage, lib, overrideCC, pkgs, buildPackages, fetchpatch, openssl, python3, nixsgx, nodejs_18, enableNpm ? false }:
let
  callPackage' = p: a: callPackage p (a // { inherit (nixsgx) libuv; });
  nodejs_libuv = nodejs_18.override { callPackage = callPackage'; };
  nodejs_patched = nodejs_libuv.overrideAttrs (prevAttrs: {
    inherit enableNpm;
    configureFlags = prevAttrs.configureFlags ++ [ "--without-node-snapshot" ];
  });
in
nodejs_patched
