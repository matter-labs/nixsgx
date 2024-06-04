# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
_:
{
  mkSGXContainer =
    { lib
    , pkgs
    , coreutils
    , curl
    , nixsgx
    , openssl
    , packages
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
    , sigFile ? null
    , extendedPackages ? [ ]
    , customRecursiveMerge ? null
    }:
      assert lib.assertMsg (!(isAzure && sgx_default_qcnl_conf != null)) "sgx_default_qcnl_conf can't be set for Azure";
      let
        recursiveMerge = attrList:
          with lib;
          let
            f = attrPath:
              zipAttrsWith (n: values:
                if tail values == [ ]
                then head values
                else if all isList values
                then unique (concatLists values)
                else if all isAttrs values
                then f (attrPath ++ [ n ]) values
                else last values
              );
          in
          f [ ] attrList;

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
            entrypoint = "file:{{ gramine.libos }}";
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

        mergedManifest = ((if customRecursiveMerge == null then recursiveMerge else customRecursiveMerge) [ manifest_base manifest ])
          # Don't merge the `loader.argv` array
          // { loader.argv = lib.attrsets.attrByPath [ "loader" "argv" ] manifest_base.loader.argv manifest; };

        tomlFormat = pkgs.formats.toml { };
        manifestFile = tomlFormat.generate "${name}.manifest.toml" mergedManifest;

        contents = pkgs.buildEnv {
          name = "image-root";

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
              ln -s ${manifestFile} $out/${appDir}/${name}.manifest.toml
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
          name = "extended-root";

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
          Cmd = [ "${extraCmd}; [[ -r /var/run/aesmd/aesm.socket ]] || restart-aesmd >&2; exec gramine-sgx ${name}" ];
          WorkingDir = "${appDir}";
        };


        # create a base image with the nix store included, because the derived image
        # will run gramine-sgx-sign and has does not include store paths,
        # otherwise all store paths from the `fakeRootCommands` will be included.
        appImage = pkgs.dockerTools.buildLayeredImage { name = "${name}-app"; inherit contents; };

        addGramineManifest = fromImage:
          pkgs.dockerTools.buildLayeredImage
            {
              name = "${name}-manifest";
              inherit tag;
              inherit contents;
              inherit fromImage;

              includeStorePaths = false;
              enableFakechroot = true;
              fakeRootCommands = ''
                (
                  set -e
                  cd ${appDir}
                  HOME=${appDir} ${nixsgx.gramine}/bin/gramine-manifest ${manifestFile} ${name}.manifest;
                  ${nixsgx.gramine}/bin/gramine-sgx-sign \
                    --manifest ${name}.manifest \
                    --output ${name}.manifest.sgx \
                    --key ${keyfile};
                  eval "${extraChrootCommands}"
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
                  mkdir -p app
                  cp ${sigFile} app/nixsgx-test-sgx-azure.sig
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
      injectSigFile (extendImage (addGramineManifest appImage));
}
