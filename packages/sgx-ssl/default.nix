{ stdenv
, callPackage
, fetchFromGitHub
, fetchurl
, lib
, perl
, nixsgx
, which
, debug ? false
}:
let
  inherit (nixsgx) sgx-sdk;
  sgxVersion = sgx-sdk.versionTag;
  opensslVersion = "3.0.14";
in
stdenv.mkDerivation {
  pname = "sgx-ssl" + lib.optionalString debug "-debug";
  version = "${sgxVersion}_${opensslVersion}";

  src = fetchFromGitHub {
    owner = "intel";
    repo = "intel-sgx-ssl";
    rev = "3.0_Rev4";
    hash = "sha256-RNAMmm2UNbIziBqu4RioPDb1/3TBd+MCsJ8PeCHWhL0=";
  };

  postUnpack =
    let
      opensslSourceArchive = fetchurl {
        url = "https://www.openssl.org/source/openssl-${opensslVersion}.tar.gz";
        hash = "sha256-7soDXU3U6E/CWEbZUtpil0hK+gZQpvhMaC453zpBI8o=";
      };
    in
    ''
      ln -s ${opensslSourceArchive} $sourceRoot/openssl_source/openssl-${opensslVersion}.tar.gz
    '';

  postPatch = ''
    patchShebangs Linux/build_openssl.sh

    # Skip the tests. Build and run separately (see below).
    substituteInPlace Linux/sgx/Makefile \
      --replace-fail '$(MAKE) -C $(TEST_DIR) all' \
                     'bash -c "true"'
  '';

  nativeBuildInputs = [
    perl
    sgx-sdk
    which
  ];

  makeFlags = [
    "-C Linux"
  ] ++ lib.optionals debug [
    "DEBUG=1"
  ];

  installFlags = [
    "DESTDIR=$(out)"
  ];

  # These tests build on any x86_64-linux but BOTH SIM and HW will only _run_ on
  # real Intel hardware. Split these out so OfBorg doesn't choke on this pkg.
  #
  # ```
  # nix run .#sgx-ssl.tests.HW
  # nix run .#sgx-ssl.tests.SIM
  # ```
  passthru.tests = {
    HW = callPackage ./tests.nix { sgxMode = "HW"; inherit opensslVersion; };
    SIM = callPackage ./tests.nix { sgxMode = "SIM"; inherit opensslVersion; };
  };

  meta = {
    description = "Cryptographic library for Intel SGX enclave applications based on OpenSSL";
    homepage = "https://github.com/intel/intel-sgx-ssl";
    maintainers = with lib.maintainers; [ phlip9 trundle veehaitch ];
    platforms = [ "x86_64-linux" ];
    license = with lib.licenses; [ bsd3 openssl ];
  };
}
