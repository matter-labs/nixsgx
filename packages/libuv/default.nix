{ lib
, libuv
}:
libuv.overrideAttrs (prevAttrs: {
    separateDebugInfo = false;
    patches = (prevAttrs.patches or [ ]) ++ [
      ./no-getifaddr.patch
      ./no-eventfd.patch
    ];
  })
