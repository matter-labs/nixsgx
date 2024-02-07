{ lib
, buildEnv
, busybox
, python3
, dockerTools
, nixsgx
}:
dockerTools.buildLayeredImage {
  name = "gramine-azure";
  tag = "latest";

  contents = buildEnv {
    name = "image-root";
    paths = [
      busybox
      nixsgx.azure-dcap-client
      nixsgx.sgx-psw
      nixsgx.sgx-dcap.quote_verify
      nixsgx.gramine
    ];

    pathsToLink = [ "/bin" "/lib" "/etc" ];
    postBuild = ''
      	mkdir -p $out/var
      	ln -s /run $out/var/run
    '';
  };
}
