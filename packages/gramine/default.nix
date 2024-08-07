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
, pkg-config
, autoconf
, gawk
, bison
, patchelf
, which
, ...
}:
let
  gcc-wrap = fetchurl {
    url = "https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/gcc-10.2.0.tar.gz";
    hash = "sha256-J+h53MxjnNewzAjtV1wWaUkleVKbU8n/J7C5YmX6hn0=";
  };
  tomlc99-wrap = fetchurl {
    url = "https://github.com/cktan/tomlc99/archive/208203af46bdbdb29ba199660ed78d09c220b6c5.tar.gz";
    hash = "sha256-cxORP94awLCjGjTk/I4QSMDLGwgT59okpEtMw8gPDok=";
  };
  cjson-wrap = fetchurl {
    url = "https://github.com/DaveGamble/cJSON/archive/v1.7.12.tar.gz";
    hash = "sha256-dgaHZlq0Glz/nECxBTwZVyvNqt7xGU5cuhteb4JGhuc=";
  };
  curl-wrap = fetchurl {
    url = "https://curl.se/download/curl-8.7.1.tar.gz";
    hash = "sha256-+RJJyH9o6gDPJ8RP36WnhCPkHnG31AjlkBqYltkFxJU=";
  };
  mbedtls-wrap = fetchurl {
    url = "https://github.com/ARMmbed/mbedtls/archive/mbedtls-3.5.2.tar.gz";
    hash = "sha256-7t7MRos/jQUu8FqdQr9j8EyKHFDRxalMJRxoE2WixyM=";
  };
  uthash-wrap = fetchurl {
    url = "https://github.com/troydhanson/uthash/archive/v2.1.0.tar.gz";
    hash = "sha256-FSzNjmTQ9JU3cjLjlk0Gx+yLuMP70yF/ilcCYU+aZp4=";
  };
  glibc-wrap = fetchurl {
    url = "https://ftp.gnu.org/gnu/glibc/glibc-2.39.tar.gz";
    hash = "sha256-l/hPO3WIzVQJOm9jibDBqB5w2ZcI10ljouPqt8fclC0=";
  };

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
  version = "1.7";

  src = pkgs.fetchFromGitHub {
    owner = "gramineproject";
    repo = "gramine";
    rev = "v1.7";
    hash = "sha256-QHgRGIx4jnTh0O3ihJbnuPwTdygJ03zpL2bdqAN9+sA=";
    fetchSubmodules = true;
  };

  patches = [
    # Add locking around read/write on encrypted pipes
    (fetchpatch {
      url = "https://github.com/gramineproject/gramine/commit/cd68a460abf9db2295f5dc5cf292b8678741fb22.patch";
      hash = "sha256-KRgcFiZWCOz1x8O0cgL7aZ1xG9bdZDPwRKSgqOWJ2nQ=";
    })
  ];

  outputs = [ "out" "dev" ];

  # Unpack subproject sources
  postUnpack = ''(
    cd "$sourceRoot/subprojects"
    tar -zxf ${gcc-wrap}
    cp -av packagefiles/gcc-10.2.0/. gcc-10.2.0
    tar -zxf ${tomlc99-wrap}
    cp -av packagefiles/tomlc99/. tomlc99-208203af46bdbdb29ba199660ed78d09c220b6c5
    tar -zxf ${cjson-wrap}
    cp -av packagefiles/cJSON/. cJSON-1.7.12
    tar -zxf ${curl-wrap}
    cp -av packagefiles/curl-8.7.1/. curl-8.7.1
    mkdir mbedtls-mbedtls-3.5.2
    tar -zxf ${mbedtls-wrap} -C mbedtls-mbedtls-3.5.2
    cp -av packagefiles/mbedtls/. mbedtls-mbedtls-3.5.2
    tar -zxf ${uthash-wrap}
    cp -av packagefiles/uthash/. uthash-2.1.0
    mkdir glibc-2.39-1
    tar -zxf ${glibc-wrap} -C glibc-2.39-1
    cp -av packagefiles/glibc-2.39/. glibc-2.39-1
    sed -i -e 's#set -e#set -ex#g' glibc-2.39-1/compile.sh
  )'';

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
  ];

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
    nixsgx.protobufc
    nixsgx.protobufc.dev
    nixsgx.sgx-dcap.dev
    nixsgx.sgx-dcap.quote_verify
    autoconf
    gawk
    bison
    patchelf
    which
  ];

  buildInputs = [
    nixsgx.protobufc.dev
    nixsgx.protobufc.lib
    bash
  ];

  propagatedBuildInputs = [
    (python.withPackages my-python-packages)
  ];

  #doCheck = false;

  meta = with lib; {
    description = "A lightweight usermode guest OS designed to run a single Linux application";
    homepage = "https://gramine.readthedocs.io/";
    platforms = [ "x86_64-linux" ];
    license = with licenses; [ lgpl3 ];
  };
}
