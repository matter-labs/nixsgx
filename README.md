# nixsgx

This repository contains a Nix flake with up-to-date packages for the Intel SGX SDK and gramine.

Hopefully most of the packages will be upstreamed to nixpkgs at some point.

All package builds should be reproducible and therefore can be used to build reproducible enclave images.

## Usage

### Test enclave

A testing enclave container is provided and can be ran like so:

```sh
# Build the dcap (or azure) container variant
nix build .#nixsgx-test-sgx-dcap

# Load image into docker
docker load < result

# Run the enclave, binding the sgx devices
docker run -i --init --rm \
  --device /dev/sgx_enclave \
  --device /dev/sgx_provision \
  nixsgx-test-sgx-dcap:latest
```

> Note: An external aesmd instance can be provided by mounting the socket to the container: `-v /var/run/aesmd/aesm.socket:/var/run/aesmd/aesm.socket`

### Reference projects

The following projects provide reproducible enclaves using nixsgx:

- https://github.com/matter-labs/teepot
- https://github.com/matter-labs/era-fee-withdrawer/tree/gramine-sgx
