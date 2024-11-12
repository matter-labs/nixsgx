{ lib
, pkgs
, writeClosure
, coreutils
, curl
, nixsgx
, openssl
, packages
, rsync
, entrypoint
, name
, tag ? null
, keyfile ? ./test-enclave-key.pem
, isAzure ? false
, manifest ? { }
, sgx_default_qcnl_conf ? null
, extraCmd ? ":"
, extraPostBuild ? ""
, extraChrootCommands ? ""
, appDir ? "/app"
, appName ? "app"
, sigFile ? null
, extendedPackages ? [ ]
, customRecursiveMerge ? null
}:
assert lib.assertMsg (!(isAzure && sgx_default_qcnl_conf != null)) "sgx_default_qcnl_conf can't be set for Azure";
let
  manifestRecursiveMerge =
    base: mod: with lib.attrsets; let
      mergeByPathWithOp = path: action: setAttrByPath path (
        if hasAttrByPath path mod
        then action (getAttrFromPath path base) (getAttrFromPath path mod)
        else getAttrFromPath path base
      );
      mergeListByPath = path: mergeByPathWithOp path (a: b: a ++ b);
      mergeEnvPathByPath = path: mergeByPathWithOp path (a: b: a + ":" + b);
    in
    recursiveUpdate base (recursiveUpdate mod (
      # manually merge the relevant lists / strings
      mergeListByPath [ "fs" "mounts" ]
      // mergeListByPath [ "sgx" "trusted_files" ]
      // mergeEnvPathByPath [ "loader" "env" "LD_LIBRARY_PATH" ]
    ));
  manifest_base = {
    libos = { inherit entrypoint; };
    fs = {
      mounts = [
        { path = "/var/tmp"; type = "tmpfs"; }
        { path = "/tmp"; type = "tmpfs"; }
        { path = "${appDir}/.dcap-qcnl"; type = "tmpfs"; }
        { path = "${appDir}/.az-dcap-client"; type = "tmpfs"; }
      ];
      root = { uri = "file:/"; };
      start_dir = "${appDir}";
    };
    loader = {
      argv = [ entrypoint ];
      entrypoint.uri = "file:{{ gramine.libos }}";
      env = {
        AZDCAP_COLLATERAL_VERSION = "v4";
        AZDCAP_DEBUG_LOG_LEVEL = "ignore";
        HOME = "${appDir}";
        LD_LIBRARY_PATH = (lib.makeLibraryPath [
          (if isAzure then nixsgx.azure-dcap-client.out else nixsgx.sgx-dcap.default_qpl)
          pkgs.curl.out
        ]) + ":{{ gramine.runtimedir() }}:/lib";
        MALLOC_ARENA_MAX = "1";
        PATH = "/bin";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      };
      log_level = "error";
    };
    sgx = {
      remote_attestation = "dcap";
      trusted_files = [
        "file:${appDir}/"
        "file:/bin/"
        "file:/etc/gai.conf"
        "file:/etc/ssl/certs/ca-bundle.crt"
        "file:/lib/"
        "file:/nix/"
        "file:{{ gramine.libos }}"
        "file:{{ gramine.runtimedir() }}/"
      ] ++ (if !isAzure then [
        "file:/etc/sgx_default_qcnl.conf"
      ] else [ ]);
    };
    sys = {
      enable_extra_runtime_domain_names_conf = true;
      enable_sigterm_injection = true;
    };
  };

  mergedManifest = (if customRecursiveMerge == null then manifestRecursiveMerge else customRecursiveMerge) manifest_base manifest;

  tomlFormat = pkgs.formats.toml { };
  manifestFile = tomlFormat.generate "${name}.manifest.toml" mergedManifest;

  contents = pkgs.buildEnv {
    name = "image-root-${appName}";

    paths = with pkgs.dockerTools; with nixsgx;[
      openssl.out
      curl.out
      gramine
      sgx-dcap.quote_verify
      caCertificates
    ]
    ++ (if isAzure then [
      azure-dcap-client
    ] else [
      sgx-dcap.default_qpl
    ])
    ++ packages;

    pathsToLink = [ "/bin" "/lib" "/etc" "/share" "${appDir}" ];
    postBuild = ''
      (
        set -e
        mkdir -p $out/{etc,var/run}
        mkdir -p $out/${appDir}/{.dcap-qcnl,.az-dcap-client}
        ln -s ${manifestFile} $out/${appDir}/${appName}.manifest.toml
        # Increase IPv4 address priority
        printf "precedence ::ffff:0:0/96  100\n" > $out/etc/gai.conf
        ${
            if sgx_default_qcnl_conf != null then
                "rm -f $out/etc/sgx_default_qcnl.conf; ln -s ${sgx_default_qcnl_conf} $out/etc/sgx_default_qcnl.conf;"
            else ""
        }
        eval "${extraPostBuild}"
      )
    '';
  };

  extendedContents = pkgs.buildEnv {
    name = "extended-root-${appName}";

    paths = with pkgs.dockerTools; with nixsgx;[
      coreutils
      restart-aesmd
      sgx-psw
      usrBinEnv
      binSh
      fakeNss
    ] ++ extendedPackages;

    pathsToLink = [ "/bin" "/lib" "/etc" "/share" ];

    postBuild =
      if sgx_default_qcnl_conf != null then ''
        (
          set -e
          mkdir -p $out/etc
          rm -f $out/etc/sgx_default_qcnl.conf
          ln -s ${sgx_default_qcnl_conf} $out/etc/sgx_default_qcnl.conf
        )
      '' else null;
  };

  config = {
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "HOME=${appDir}"
      "LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.curl.out (if isAzure then nixsgx.azure-dcap-client.out else nixsgx.sgx-dcap.default_qpl)]}"
    ];
    Entrypoint = [ "/bin/sh" "-c" ];
    Cmd = [
      ''
        ${extraCmd};
        if [ -n "$GRAMINE_DIRECT" ]; then
            exec gramine-direct ${appName};
        else
            [[ -r /var/run/aesmd/aesm.socket ]] || restart-aesmd >&2;
            exec gramine-sgx ${appName};
        fi
      ''
    ];
    WorkingDir = "${appDir}";
  };


  # create a base image with the nix store included, because the derived image
  # will run gramine-sgx-sign and has does not include store paths,
  # otherwise all store paths from the `fakeRootCommands` will be included.
  appImage = pkgs.dockerTools.buildLayeredImage { name = "${name}-app"; inherit contents; };

  addGramineManifest = fromImage:
    let
      mkNixStore = contents:
        let
          contentsList = if builtins.isList contents then contents else [ contents ];
        in
        ''
          ${rsync}/bin/rsync -ar --files-from=${writeClosure contentsList} / ./
        '';

    in
    pkgs.dockerTools.buildLayeredImage
      {
        name = "${name}-manifest-${appName}";
        inherit tag;
        inherit contents;
        inherit fromImage;

        includeStorePaths = false;
        extraCommands = (mkNixStore contents) + ''
          (
            set -e
            CHROOT=$(pwd)
            appDir="${appDir}"
            cd "''${appDir#/}"
            HOME="${appDir}" ${nixsgx.gramine}/bin/gramine-manifest \
                --chroot "$CHROOT" \
                ${manifestFile} ${appName}.manifest;
            ${nixsgx.gramine}/bin/gramine-sgx-sign \
              --chroot "$CHROOT" \
              --manifest ${appName}.manifest \
              --output ${appName}.manifest.sgx \
              --key ${keyfile};
            eval "${extraChrootCommands}"
            cd "$CHROOT"
            chmod u+wx -R nix
            rm -fr nix
          )
        '';
      };

  injectSigFile = fromImage:
    if sigFile != null then
      pkgs.dockerTools.buildLayeredImage
        {
          inherit name;
          inherit config;
          inherit tag;
          inherit fromImage;

          includeStorePaths = false;
          extraCommands = ''
            mkdir -p ${appDir}
            cp ${sigFile} ${appDir}/${appName}.sig
          '';
        }
    else fromImage;

  extendImage = fromImage:
    pkgs.dockerTools.buildLayeredImage
      {
        inherit name;
        inherit tag;
        inherit config;
        inherit fromImage;
        contents = extendedContents;
      };
in
injectSigFile (extendImage (addGramineManifest appImage))
