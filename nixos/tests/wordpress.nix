import ./make-test-python.nix ({ pkgs, ... }:

{
  name = "wordpress";
  meta = with pkgs.stdenv.lib.maintainers; {
    maintainers = [ b42 grahamc ]; # under duress!
  };

  machine =
    { ... }:
    { services.httpd.adminAddr = "webmaster@site.local";
      services.httpd.logPerVirtualHost = true;

      services.wordpress."site1.local" = {
        database.tablePrefix = "site1_";
      };

      services.wordpress."site2.local" = {
        database.tablePrefix = "site2_";
      };

      networking.hosts."127.0.0.1" = [ "site1.local" "site2.local" ];
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("httpd")

    for site in ["site1.local", "site2.local"]:
        machine.wait_for_unit(f"phpfpm-wordpress-{site}")

        machine.succeed(f"curl -L {site} | grep 'Welcome to the famous'")

        machine.succeed(
            f"systemctl --no-pager show wordpress-init-{site}.service | grep 'ExecStart=.*status=0'"
        )
        nonce_regex = "^define.*NONCE_SALT.{64,};$"
        machine.succeed(
            f"grep -E '{nonce_regex}' /var/lib/wordpress/{site}/secret-keys.php"
        )
  '';
})
