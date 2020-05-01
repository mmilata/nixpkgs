import ./make-test-python.nix ({ pkgs, lib, ... }: let
  cert = pkgs.runCommand "nginx-cert" { } ''
    mkdir $out
    ${pkgs.openssl}/bin/openssl req \
      -x509 \
      -newkey rsa:4096 \
      -keyout $out/server.key \
      -out $out/server.crt \
      -days 365 \
      -nodes \
      -subj '/CN=server' \
      -addext "subjectAltName = DNS:server"
    '';
in
rec {
  name = "jitsi-meet";
  meta = with pkgs.stdenv.lib.maintainers; {
    maintainers = [ ];
  };

  enableOCR = true;
  user = "alice";

  nodes = rec {
    client1 = { nodes, config, pkgs, ... }: {
      imports = [ ./common/user-account.nix ./common/x11.nix ];

      test-support.displayManager.auto.user = user;

      virtualisation.memorySize = 1024;
      environment.systemPackages = with pkgs; [ chromium ffmpeg imagemagick ];
      boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
      fonts.enableDefaultFonts = true;
    };

    client2 = client1;

    server = { nodes, pkgs, ... }: {
      virtualisation.memorySize = 1024;

      services.jitsi-meet = {
        enable = true;
        hostName = "server";
      };
      services.jitsi-videobridge.openFirewall = true;

      networking.firewall.allowedTCPPorts = [ 80 443 ];

      services.nginx.virtualHosts.server = {
        forceSSL = true;
        sslCertificate = "${cert}/server.crt";
        sslCertificateKey = "${cert}/server.key";
      };
    };
  };

  testScript = let
    fakeCam = text: pkgs.writeScript "camera.sh" ''
      modprobe v4l2loopback exclusive_caps=1
      convert -border 230 -font DejaVu-Serif -pointsize 48 -extent 640x480 label:'${text}' /tmp/image.png
      ffmpeg -loop 1 -re -i /tmp/image.png -f v4l2 -vcodec rawvideo -pix_fmt yuv420p /dev/video0 & disown
    '';
  in
  ''
    import shlex


    # Run as user alice
    def ru(cmd):
        return "su - ${user} -c " + shlex.quote(cmd)


    server.wait_for_unit("jitsi-videobridge2.service")
    server.wait_for_unit("jicofo.service")
    server.wait_for_unit("nginx.service")
    server.wait_for_unit("prosody.service")

    server.wait_until_succeeds(
        "journalctl -b -u jitsi-videobridge2 -o cat | grep -q 'Performed a successful health check'"
    )
    server.wait_until_succeeds(
        "journalctl -b -u jicofo -o cat | grep -q 'connected .JID: focus@auth.server'"
    )
    server.wait_until_succeeds(
        "journalctl -b -u prosody -o cat | grep -q 'Authenticated as focus@auth.server'"
    )
    server.wait_until_succeeds(
        "journalctl -b -u prosody -o cat | grep -q 'focus.server:component: External component successfully authenticated'"
    )
    server.wait_until_succeeds(
        "journalctl -b -u prosody -o cat | grep -q 'Authenticated as jvb@auth.server'"
    )

    client1.execute("${fakeCam "Lorem ipsum"}")
    client2.execute("${fakeCam "Good day sir"}")

    for client in (client1, client2):
        client.execute(ru("mkdir -p /home/${user}/.pki/nssdb"))
        client.execute(
            ru(
                "${pkgs.nss.tools}/bin/certutil -d sql:/home/${user}/.pki/nssdb -A -n jitsi -i ${cert}/server.crt -t TCPc,,"
            )
        )
        client.wait_for_x()

    for client in (client1, client2):
        client.execute(ru("rm -rf /home/${user}/.config/chromium"))
        client.execute(
            ru(
                "chromium --use-fake-ui-for-media-stream --start-maximized https://server/SomeJitsiRoomName &"
            )
        )

    client1.sleep(60)
    client1.screenshot("client1")
    client2.screenshot("client2")

    client1.wait_for_text("Good day sir")
    client2.wait_for_text("Lorem ipsum")
  '';
})
