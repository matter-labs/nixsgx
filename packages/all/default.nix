{ lib
, buildEnv
, stdenv
, symlinkJoin
, nixsgx
}:
let
  container = stdenv.mkDerivation {
    name = "container";

    src = with nixsgx; [
      docker-gramine-azure
      docker-gramine-dcap
    ];

    unpackPhase = "true";

    installPhase = ''
      set -x
      mkdir -p $out
      cp -vr $src $out
    '';
  };
in
symlinkJoin {
  name = "all";
  paths = with nixsgx;[
    azure-dcap-client
    container
    gramine
    libuv
    nodejs
    protobufc
    restart-aesmd
    sgx-dcap
    sgx-psw
    sgx-sdk
    sgx-ssl
  ];
}
