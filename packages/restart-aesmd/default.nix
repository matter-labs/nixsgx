{ pkgs
, lib
, nixsgx
, ...
}:
pkgs.writeShellScriptBin "restart-aesmd" ''
  ${pkgs.coreutils}/bin/mkdir -p /var/run/aesmd
  ${pkgs.killall}/bin/killall -q aesm_service
  exec ${nixsgx.sgx-psw}/bin/aesm_service --no-syslog
''
