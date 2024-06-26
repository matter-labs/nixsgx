# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
{ nixsgx }: nixsgx.nixsgx-test-sgx-dcap.override {
  container-name = "nixsgx-test-sgx-azure";
  isAzure = true;
}
