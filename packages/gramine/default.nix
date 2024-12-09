{ pkgs
, lib
, nixsgx
, fetchurl
, fetchpatch
, bash
, meson
, nasm
, ninja
, cmake
, cacert
, pkg-config
, autoconf
, perl
, gawk
, bison
, patchelf
, protobufc
, which
}:
let
  python = pkgs.python3;

  my-python-packages = ps: with ps; [
    click
    jinja2
    pyelftools
    tomli
    tomli-w
    cryptography
    voluptuous
  ];
in
python.pkgs.buildPythonPackage {
  pname = "gramine";
  version = "1.8";

  src = pkgs.fetchFromGitHub {
    owner = "gramineproject";
    repo = "gramine";
    rev = "v1.8";
    hash = "sha256-yz7hVEJAqYQbzdCEVG1c/mVpuBDQtv/MUSCcH60pN5g=";
    fetchSubmodules = true;
    postFetch = ''
      (
        cd "$out"
        export NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
        for prj in subprojects/*.wrap; do
          ${lib.getExe meson} subprojects download "$(basename "$prj" .wrap)"
          rm -rf subprojects/$(basename "$prj" .wrap)/.git
        done
      )
    '';
  };

  outputs = [ "out" "dev" ];

  postPatch = ''
    patchShebangs --build $(find . -name '*.sh')
    patchShebangs --build $(find . -name '*.py')
    patchShebangs --build $(find . -name 'configure')
  '';

  mesonFlags = [
    "--buildtype=release"
    "-Ddirect=enabled"
    "-Dsgx=enabled"
    "-Dsgx_driver=upstream"
    "-Dc_args=-Wno-error=attributes"
    "-Dc_args=-Wno-attributes"
  ];

  env.PERL = lib.getExe perl;

  # will be enabled by projects on demand
  hardeningDisable = [ "fortify" "pie" "stackprotector" ];

  postFixup = ''
    set -e
    rm $out/lib/*.a
    rm $out/lib/*/*/*/*.a
    patchelf --remove-rpath $out/lib/gramine/sgx/libpal.so
    patchelf --remove-rpath $out/lib/gramine/direct/loader
    patchelf --remove-rpath $out/lib/gramine/libsysdb.so
    patchelf --remove-rpath $out/lib/gramine/runtime/glibc/ld.so
    patchelf --remove-rpath $out/lib/gramine/runtime/glibc/libc.so
    patchelf --remove-rpath $out/lib/gramine/runtime/glibc/ld-linux-x86-64.so.2
  '';

  format = "other";

  nativeBuildInputs = [
    python
    meson
    nasm
    ninja
    cmake
    pkg-config
    nixsgx.sgx-sdk
    protobufc
    nixsgx.sgx-dcap.dev
    nixsgx.sgx-dcap.quote_verify
    autoconf
    gawk
    bison
    patchelf
    which
    perl
  ];

  buildInputs = [
    protobufc.dev
    protobufc.lib
    bash
  ];

  propagatedBuildInputs = [
    (python.withPackages my-python-packages)
  ];

  meta = with lib; {
    description = "A lightweight usermode guest OS designed to run a single Linux application";
    homepage = "https://gramine.readthedocs.io/";
    platforms = [ "x86_64-linux" ];
    license = with licenses; [ lgpl3 ];
  };
}
