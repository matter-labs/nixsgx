{ nodejs_18, enableNpm ? false }:
nodejs_18.overrideAttrs (prevAttrs: {
  inherit enableNpm;
  configureFlags = prevAttrs.configureFlags ++ [ "--without-node-snapshot" ];
})
