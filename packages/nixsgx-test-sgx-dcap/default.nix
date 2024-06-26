# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
{ lib
, pkgs
, inputs
, nixsgx
, hello
, isAzure ? false
, container-name ? "nixsgx-test-sgx-dcap"
, tag ? "latest"
}:
pkgs.callPackage lib.nixsgx.mkSGXContainer {
  name = container-name;
  inherit tag isAzure;

  packages = [ hello ];
  entrypoint = lib.meta.getExe hello;

  extraCmd = "echo \"Starting ${container-name}\"; gramine-sgx-sigstruct-view app.sig";

  manifest = {
    sgx = {
      edmm_enable = false;
      enclave_size = "32M";
      max_threads = 2;
    };
  };
}
