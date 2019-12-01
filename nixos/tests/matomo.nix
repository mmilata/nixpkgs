{ system ? builtins.currentSystem, config ? { }
, pkgs ? import ../.. { inherit system config; }
, useBeta ? true }:

with import ../lib/testing-python.nix { inherit system pkgs; };
with pkgs.lib;

makeTest {
  name = "matomo${optionalString useBeta "-beta"}";
  meta.maintainers = with maintainers; [ florianjacob kiwi mmilata ];

  machine = { config, pkgs, ... }: {
    services.matomo = {
      package = if useBeta then pkgs.matomo-beta else pkgs.matomo;
      enable = true;
      nginx = {
        forceSSL = false;
        enableACME = false;
      };
    };
    services.mysql = {
      enable = true;
      package = pkgs.mysql;
    };
    services.nginx.enable = true;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("mysql.service")
    machine.wait_for_unit("phpfpm-matomo.service")
    machine.wait_for_unit("nginx.service")

    # without the grep the command does not produce valid utf-8 for some reason
    with subtest("welcome screen loads"):
        machine.succeed(
            "curl -sSfL http://localhost/ | grep '<title>Matomo[^<]*Installation'"
        )
  '';
}
