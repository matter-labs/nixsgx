{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, cmake
, boost
, python3
, openssl
, which
, wget
, curl
, zip
, nixsgx
, makeWrapper
}:
stdenv.mkDerivation rec {
  pname = "sgx-dcap";
  version = "1.21";

  postUnpack =
    let
      dcap = rec {
        filename = "prebuilt_dcap_${version}.tar.gz";
        prebuilt = fetchurl {
          url = "https://download.01.org/intel-sgx/sgx-dcap/${version}/linux/${filename}";
          hash = "sha256-/PPD2MyNxoCwzNljIFcpkFvItXbyvymsJ7+Uf4IyZuk=";
        };
      };
    in
    ''
      # Make sure we use the correct version of prebuilt DCAP
      grep -q 'ae_file_name=${dcap.filename}' "$sourceRoot/QuoteGeneration/download_prebuilt.sh" \
        || (echo "Could not find expected prebuilt DCAP ${dcap.filename} in dcap source" >&2 && grep 'ae_file_name' "$sourceRoot/QuoteGeneration/download_prebuilt.sh"  && exit 1)

      tar -zxf ${dcap.prebuilt} -C $sourceRoot/QuoteGeneration/
    '';

  src = fetchFromGitHub {
    owner = "intel";
    repo = "SGXDataCenterAttestationPrimitives";
    rev = "DCAP_${version}";
    hash = "sha256-Vp8R4W6qdPTGJFNJrPPKe9Oqxxj+UIdZf2GSL+gCyjU=";
    fetchSubmodules = true;
  };

  outputs = [
    "out"
    "dev"
    "ae_id_enclave"
    "ae_qe3"
    "ae_qve"
    "ae_tdqe"
    "pce_logic"
    "qe3_logic"
    "default_qpl"
    "ql"
    "quote_verify"
    "ra_network"
    "ra_uefi"
    "tdx_logic"
    "libtdx_attest"
    "pck_id_retrieval_tool"
  ];

  patches = [
    # make tarballs reproducible
    ./SGXDataCenterAttestationPrimitives-tarball-repro.patch
    # sigh... Intel!
    ./SGXDataCenterAttestationPrimitives-parallel-make.patch
    # make config work without a dedicated PCCS server by default
    ./SGXDataCenterAttestationPrimitives-sgx_default_qcnl_conf.patch
  ];

  postPatch = ''
    patchShebangs --build $(find . -name '*.sh')
  '';

  preBuild = ''
    makeFlagsArray+=(SGX_SDK="${nixsgx.sgx-sdk}" SGXSSL_PACKAGE_PATH="${nixsgx.sgx-ssl}")
  '';

  # sigh... Intel!
  enableParallelBuilding = true;
  dontUseCmakeConfigure = true;

  # setOutputFlags = false;
  # moveToDev = false;

  # sigh... Intel!
  installPhase = ''
    #set -xe
    runHook preInstall

    # sigh... Intel!
    mkdir -p QuoteGeneration/pccs/lib/
    cp tools/PCKCertSelection/out/libPCKCertSelection.so QuoteGeneration/pccs/lib/

    mkdir -p "$out"

    dcap_pkgdirs=(
        ./QuoteGeneration/installer/linux/common/libsgx-ae-id-enclave
        ./QuoteGeneration/installer/linux/common/libsgx-ae-qe3
        ./QuoteGeneration/installer/linux/common/libsgx-ae-qve
        ./QuoteGeneration/installer/linux/common/libsgx-ae-tdqe
        ./QuoteGeneration/installer/linux/common/libsgx-dcap-default-qpl
        ./QuoteGeneration/installer/linux/common/libsgx-dcap-ql
        ./QuoteGeneration/installer/linux/common/libsgx-dcap-quote-verify
        ./QuoteGeneration/installer/linux/common/libsgx-pce-logic
        ./QuoteGeneration/installer/linux/common/libsgx-qe3-logic
        ./QuoteGeneration/installer/linux/common/libsgx-tdx-logic
        ./QuoteGeneration/installer/linux/common/libtdx-attest
        ./tools/SGXPlatformRegistration/package/installer/common/libsgx-ra-network
        ./tools/SGXPlatformRegistration/package/installer/common/libsgx-ra-uefi
        ./tools/PCKRetrievalTool/installer/common/sgx-pck-id-retrieval-tool
        #./QuoteGeneration/installer/linux/common/sgx-dcap-pccs
    )

    for src in ''${dcap_pkgdirs[@]}; do
        dst="$out/$src"
        echo "Processing $src"
        "$src"/createTarball.sh
        mkdir -p "$dst"
        make DESTDIR="$dst/output" -C "$src"/output install
    done

    dcap_map=(
        QuoteGeneration/installer/linux/common/libsgx-ae-id-enclave/output
        "$ae_id_enclave"
        QuoteGeneration/installer/linux/common/libsgx-ae-qe3/output
        "$ae_qe3"
        QuoteGeneration/installer/linux/common/libsgx-ae-qve/output
        "$ae_qve"
        QuoteGeneration/installer/linux/common/libsgx-ae-tdqe/output
        "$ae_tdqe"
        QuoteGeneration/installer/linux/common/libsgx-pce-logic/output
        "$pce_logic"
        QuoteGeneration/installer/linux/common/libsgx-qe3-logic/output
        "$qe3_logic"
        QuoteGeneration/installer/linux/common/libsgx-dcap-default-qpl/output/libsgx-dcap-default-qpl
        "$default_qpl"
        QuoteGeneration/installer/linux/common/libsgx-dcap-ql/output/libsgx-dcap-ql
        "$ql"
        QuoteGeneration/installer/linux/common/libsgx-dcap-quote-verify/output/libsgx-dcap-quote-verify
        "$quote_verify"
        QuoteGeneration/installer/linux/common/libsgx-tdx-logic/output/libsgx-tdx-logic
        "$tdx_logic"
        QuoteGeneration/installer/linux/common/libtdx-attest/output/libtdx-attest
        "$libtdx_attest"
        tools/SGXPlatformRegistration/package/installer/common/libsgx-ra-network/output/libsgx-ra-network
        "$ra_network"
        tools/SGXPlatformRegistration/package/installer/common/libsgx-ra-uefi/output/libsgx-ra-uefi
        "$ra_uefi"
        tools/PCKRetrievalTool/installer/common/sgx-pck-id-retrieval-tool/output
        "$pck_id_retrieval_tool"
        #QuoteGeneration/installer/linux/common/sgx-dcap-pccs/output
        #"$pccs"
        #    sgx-ra-service
        #    tdx-qgs
    )

    for ((i = 0 ; i < ''${#dcap_map[@]} ; i+=2 )); do
        src="''${dcap_map[i]}"
        dst="''${dcap_map[i+1]}"

        echo "Processing $src"

        mkdir -p "$dst"

        if [[ -d "$out/$src/opt/intel" ]]; then
          find "$out/$src/opt/intel"
          moveToOutput "$src/opt/intel" "$dst"
          mkdir "$dst/bin"
          mv "$dst/$src/opt/intel"/*/* "$dst/bin/"
        fi

        if [[ -d "$out/$src" ]]; then
          find "$out/$src"
          moveToOutput "$src" "$dst"
        fi

        if [[ -d "$out/$src-dev" ]]; then
          find "$out/$src-dev"
          moveToOutput "$src-dev" "$dst"
        fi

        mv "$dst"/$src/* "$dst"/

        if [[ -d "$dst"/$src-dev ]]; then
          cp -a "$dst"/$src-dev/. "$dst"/
        fi

        if [[ -d "$dst"/usr ]]; then
          cp -a "$dst"/usr/. "$dst"/
          rm -fr "$dst"/usr
        fi

        [[ -d "$dst"/lib64 ]] && mv "$dst"/lib64 "$dst"/lib
        [[ -d "$dst"/opt ]] && rm -fr "$dst"/opt

        rm -fr "$dst/''${src%%/*}"
    done

    mkdir -p "$out"/share/doc
    echo Hello > "$out"/share/doc/README.md

    rm "$pck_id_retrieval_tool"/bin/lib*so*
    mkdir "$pck_id_retrieval_tool"/lib
    cp QuoteGeneration/psw/ae/data/prebuilt/libsgx_id_enclave.signed.so "$pck_id_retrieval_tool"/lib
    ln -fs ../lib/libsgx_id_enclave.signed.so "$pck_id_retrieval_tool"/bin/libsgx_id_enclave.signed.so.1
    cp QuoteGeneration/psw/ae/data/prebuilt/libsgx_pce.signed.so "$pck_id_retrieval_tool"/lib
    ln -fs ../lib/libsgx_pce.signed.so "$pck_id_retrieval_tool"/bin/libsgx_pce.signed.so.1

    #set +x
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$pck_id_retrieval_tool/bin/PCKIDRetrievalTool" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ nixsgx.sgx-psw ]}:$ra_uefi/lib:$ra_network/lib"
  '';

  nativeBuildInputs = [
    makeWrapper
    cmake
    openssl
    python3
    boost
    curl
    which
    wget
    zip
  ];

  buildInputs = [
    nixsgx.sgx-sdk
  ];

  doCheck = false;

  dontDisableStatic = false;

  meta = with lib; {
    description = "Intel(R) Software Guard Extensions Data Center Attestation Primitives";
    homepage = "https://github.com/intel/SGXDataCenterAttestationPrimitives";
    platforms = [ "x86_64-linux" ];
    license = with licenses; [ bsd3 ];
  };
}
