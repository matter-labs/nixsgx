# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
{ ... }:
final: prev:
{
  nixsgxLib.mkSGXContainer = final.lib.warn "`nixsgxLib.mkSGXContainer` is deprecated, use `pkgs.lib.tee.sgxGramineContainer`" final.lib.tee.sgxGramineContainer;

  lib = prev.lib.extend (libFinal: libPrev: {
    tee = libPrev.tee or { } // {
      sgxGramineContainer = args: final.callPackage ./sgxGramineContainer.nix args;
    };
  });
}
