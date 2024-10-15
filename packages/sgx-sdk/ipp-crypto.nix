{ gcc11Stdenv
, fetchFromGitHub
, cmake
, nasm
, openssl
, python3
, extraCmakeFlags ? [ ]
}:
gcc11Stdenv.mkDerivation rec {
  pname = "ipp-crypto";
  version = "2021.12.1";

  src = fetchFromGitHub {
    owner = "intel";
    repo = "ipp-crypto";
    rev = "ippcp_${version}";
    hash = "sha256-voxjx9Np/8jy9XS6EvUK4aW18/DGQGaPpTKm9RzuCU8=";
  };

  cmakeFlags = [
    "-DARCH=intel64"
    # sgx-sdk now requires FIPS-compliance mode turned on
    "-DIPPCP_FIPS_MODE=on"
  ] ++ extraCmakeFlags;

  nativeBuildInputs = [
    cmake
    nasm
    openssl
    python3
  ];
}
