# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
{ lib
, pkgs
, inputs
, nixsgx
, hello
}:
pkgs.callPackage lib.nixsgx.mkSGXContainer {
  name = "nixsgx-test-sgx-azure";
  tag = "latest";

  packages = [ hello ];
  entrypoint = lib.meta.getExe hello;

  isAzure = true;

  manifest = {
    sgx = {
      edmm_enable = false;
      enclave_size = "32M";
      max_threads = 2;
    };
  };
}
