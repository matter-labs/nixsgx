{ lib
, buildEnv
, dockerTools
, nixsgx
, busybox
, ...
}:
dockerTools.buildLayeredImage {
  name = "gramine-dcap";
  tag = "latest";

  contents = buildEnv {
    name = "image-root";
    paths = [
      busybox
      nixsgx.sgx-psw
      nixsgx.gramine
      nixsgx.sgx-dcap.default_qpl
      nixsgx.restart-aesmd
    ];
    pathsToLink = [ "/bin" "/lib" "/etc" ];
    postBuild = ''
      	mkdir -p $out/var
      	ln -s /run $out/var/run
    '';
  };
}
