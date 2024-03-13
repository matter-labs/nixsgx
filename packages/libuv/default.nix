{ lib
, libuv
}:
libuv.overrideAttrs (prevAttrs: {
  separateDebugInfo = false;
  patches = (prevAttrs.patches or [ ]) ++ [
    ./no-eventfd.patch
  ];
})
