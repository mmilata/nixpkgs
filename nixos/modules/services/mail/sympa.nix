{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.sympa;
  user = cfg.user;
  group = cfg.group;
  pkg = cfg.package.override { inherit (cfg) dataDir; };
  dataDir = cfg.dataDir;
  fqdns = mapAttrsToList (name: _val: name) cfg.domains;

  sympaSubServices = [
    "sympa-archive.service"
    "sympa-bounce.service"
    "sympa-bulk.service"
    "sympa-task.service"
  ];

  sympaServiceConfig = srv: {
    Type = "forking";
    Restart = "always";
    ExecStart = "${pkg}/bin/${srv}.pl";
    PIDFile = "/run/sympa/${srv}.pid";
    User = "${user}";
    Group = "${group}";
  };

  mainConfig = pkgs.writeText "sympa.conf" ''
    domain     ${if cfg.mainDomain != null then cfg.mainDomain else (head fqdns)}
    listmaster ${concatStringsSep "," cfg.listMasters}
    lang       ${cfg.lang}

    home        ${dataDir}/list_data
    arc_path    ${dataDir}/arc
    bounce_path ${dataDir}/bounce

    db_type ${cfg.database.type}
    db_name ${cfg.database.name}
    ${optionalString (cfg.database.host != null) "db_host ${cfg.database.host}"}
    ${optionalString (cfg.database.port != null) "db_port ${cfg.database.port}"}
    ${optionalString (cfg.database.user != null) "db_user ${cfg.database.user}"}
    db_passwd #dbpass#

    ${optionalString (cfg.mta.type == "postfix") ''
      sendmail         /run/wrappers/bin/sendmail
      sendmail_aliases ${dataDir}/sympa_transport

      aliases_program ${pkgs.postfix}/bin/postmap
      aliases_db_type hash
    ''}

    ${optionalString cfg.web.enable ''
      static_content_path ${dataDir}/static_content
      css_path            ${dataDir}/static_content/css
      pictures_path       ${dataDir}/static_content/pictures
      mhonarc             ${pkgs.perlPackages.MHonArc}/bin/mhonarc
    ''}

    ${cfg.extraConfig}
  '';

  robotConfig = fqdn: domain: pkgs.writeText "${fqdn}-robot.conf" ''
    ${optionalString (cfg.web.enable && domain.webHost != null) ''
      # WEB
      wwsympa_url         https://${domain.webHost}${strings.removeSuffix "/" domain.webLocation}
    ''}

    ${domain.extraConfig}
  '';

  transport = pkgs.writeText "transport.sympa" (concatStringsSep "\n" (flip map fqdns (domain: ''
    ${domain}                        error:User unknown in recipient table
    sympa@${domain}                  sympa:sympa@${domain}
    listmaster@${domain}             sympa:listmaster@${domain}
    bounce@${domain}                 sympabounce:sympa@${domain}
    abuse-feedback-report@${domain}  sympabounce:sympa@${domain}
  '')));

  virtual = pkgs.writeText "virtual.sympa" (concatStringsSep "\n" (flip map fqdns (domain: ''
    sympa-request@${domain}  postmaster@localhost
    sympa-owner@${domain}    postmaster@localhost
  '')));

  listAliases = pkgs.writeText "list_aliases.tt2" ''
    #--- [% list.name %]@[% list.domain %]: list transport map created at [% date %]
    [% list.name %]@[% list.domain %] sympa:[% list.name %]@[% list.domain %]
    [% list.name %]-request@[% list.domain %] sympa:[% list.name %]-request@[% list.domain %]
    [% list.name %]-editor@[% list.domain %] sympa:[% list.name %]-editor@[% list.domain %]
    #[% list.name %]-subscribe@[% list.domain %] sympa:[% list.name %]-subscribe@[%list.domain %]
    [% list.name %]-unsubscribe@[% list.domain %] sympa:[% list.name %]-unsubscribe@[% list.domain %]
    [% list.name %][% return_path_suffix %]@[% list.domain %] sympabounce:[% list.name %]@[% list.domain %]
  '';
in
{

  ###### interface

  options = {

    services.sympa = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Sympa mailing list manager.";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.sympa;
        description = "Which Sympa package to use.";
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/sympa";
        description = "Data directory where state is stored.";
      };

      user = mkOption {
        type = types.str;
        default = "sympa";
        description = "What to call the Sympa user (must be used only for sympa).";
      };

      group = mkOption {
        type = types.str;
        default = "sympa";
        description = "What to call the Sympa group (must be used only for sympa).";
      };

      lang = mkOption {
        type = types.str;
        default = "en_US";
        example = "cs";
        description = "Sympa language.";
      };

      listMasters = mkOption {
        type = types.listOf types.str;
        example = [ "postmaster@sympa.example.org" ];
        description = ''
          The list of the email addresses of the listmasters
          (users authorized to perform global server commands).
        '';
      };

      mainDomain = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "lists.example.org";
        description = ''
          Main domain to be used in sympa.conf.
          If null, one of the <option>domains</option> is chosen for you.
        '';
      };

      domains = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            webHost = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "archive.example.org";
              description = ''
                Domain part of the web interface URL (no web interface for this domain if null).
                DNS record of type A (or AAAA) has to exist with this value.
              '';
            };
            webLocation = mkOption {
              type = types.str;
              default = "/";
              example = "/sympa";
              description = "URL path part of the web interface.";
            };
            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = ''
                These lines go to the end of the robot.conf verbatim.
              '';
            };
          };
        });
        description = ''
          Email domains handled by this instance. There have
          to be MX records for keys of this attribute set.
        '';
        example = literalExample ''
          {
            "lists.example.org" = {
              webHost = "lists.example.org";
              webLocation = "/";
            };
            "sympa.example.com" = {
              webHost = "example.com";
              webLocation = "/sympa";
            };
          };
        '';
      };

      database = {
        type = mkOption {
          type = types.enum [ "SQLite" "PostgreSQL" "MySQL" ];
          default = "SQLite";
          example = "MySQL";
          description = "Database engine to use.";
        };

        host = mkOption {
          type = types.nullOr types.str;
          default = "127.0.0.1";
          description = "Database host address.";
        };

        port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Database port.";
        };

        name = mkOption {
          type = types.str;
          default = if cfg.database.type == "SQLite" then "${dataDir}/sympa.sqlite" else "sympa";
          description = ''
            Database name. When using SQLite this must be an absolute
            path to the database file.
          '';
        };

        user = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Database user.";
        };

        password = mkOption {
          type = types.str;
          default = "";
          description = ''
            The password corresponding to <option>database.user</option>.
            Warning: this is stored in cleartext in the Nix store!
            Use <option>database.passwordFile</option> instead.
          '';
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/keys/sympa-dbpassword";
          description = ''
            A file containing the password corresponding to
            <option>database.user</option>.
          '';
        };
      };

      web = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable Sympa web interface.";
        };

        server = mkOption {
          type = types.enum [ "nginx" "none" ];
          default = "nginx";
          description = ''
            The webserver used for the Sympa web interface. Set it to `none` if you want to configure it yourself.
            Further nginx configuration can be done by adapting <literal>services.nginx.virtualHosts.&lt;name&gt;</literal>.
          '';
        };

        https = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to use HTTPS. When nginx integration is enabled, this option forces SSL and enables ACME.
            Please note that Sympa web interface always uses https links even when this option is disabled.
          '';
        };

        fcgiProcs = mkOption {
          type = types.ints.positive;
          default = 2;
          description = "Number of FastCGI processes to fork.";
        };
      };

      mta = {
        type = mkOption {
          type = types.enum [ "postfix" "none" ];
          default = "postfix";
          description = ''
            Mail transfer agent (MTA) integration. Use `none` if you want to configure it yourself.

            The `postfix` integration sets up local Postfix instance that will pass incoming
            messages from configured domains to Sympa. You still need to configure at least
            outgoing message handling using e.g. <option>services.postfix.relayHost</option>.
          '';
        };
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "
          Extra lines to be added verbatim to the main configuration file.
        ";
      };
    };
  };

  ###### implementation

  config = mkIf cfg.enable (mkMerge [
    {

      environment = {
        systemPackages = [ pkg ];
      };

      users.users = optional (user == "sympa")
        { name = "sympa";
          description = "Sympa mailing list manager user";
          uid = config.ids.uids.sympa;
          group = group;
          home = cfg.dataDir;
          createHome = true;
        };

      users.groups =
        optional (group == "sympa")
        { name = group;
          gid = config.ids.gids.sympa;
        };

      warnings = optional (cfg.database.password != "")
        ''config.services.sympa.database.password will be stored as plaintext
          in the Nix store. Use database.passwordFile instead.'';

      # Create database passwordFile default when password is configured.
      services.sympa.database.passwordFile =
        (mkDefault (toString (pkgs.writeTextFile {
          name = "sympa-database-password";
          text = cfg.database.password;
        })));

      systemd.tmpfiles.rules = [
        "d '/run/sympa' 0755 ${user} ${group} - -"
      ];

      systemd.services.sympa = {
        description = "Sympa mailing list manager";

        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = [ pkg ];
        wants = sympaSubServices;
        before = sympaSubServices;
        serviceConfig = sympaServiceConfig "sympa_msg";

        preStart = ''
          umask 0077
          mkdir -p ${dataDir}/etc
          mkdir -p ${dataDir}/spool
          mkdir -p ${dataDir}/list_data
          mkdir -p ${dataDir}/arc
          mkdir -p ${dataDir}/bounce

          cp -f ${mainConfig} ${dataDir}/etc/sympa.conf
          DBPASS="$(head -n1 ${cfg.database.passwordFile})"
          if [ -n "$DBPASS" ]; then
              sed -e "s,#dbpass#,$DBPASS,g" \
                  -i ${dataDir}/etc/sympa.conf
          else
              sed -e "/db_passwd.*#dbpass#/d" \
                  -i ${dataDir}/etc/sympa.conf
          fi

          ${concatStringsSep "\n" (flip mapAttrsToList cfg.domains (fqdn: domain:
          ''
            mkdir -p -m 750 ${dataDir}/etc/${fqdn}
            cp -f ${robotConfig fqdn domain} ${dataDir}/etc/${fqdn}/robot.conf
            mkdir -p -m 750 ${dataDir}/list_data/${fqdn}
          ''))}

          cp -f ${virtual} ${dataDir}/virtual.sympa
          cp -f ${transport} ${dataDir}/transport.sympa
          cp -f ${listAliases} ${dataDir}/etc/list_aliases.tt2

          touch ${dataDir}/sympa_transport

          ${optionalString (cfg.mta.type == "postfix") ''
            ${pkgs.postfix}/bin/postmap hash:${dataDir}/virtual.sympa
            ${pkgs.postfix}/bin/postmap hash:${dataDir}/transport.sympa
          ''}
          ${pkg}/bin/sympa_newaliases.pl


          cp -af ${pkg}/static_content ${dataDir}/
          # Yes, wwsympa needs write access to static_content..
          chmod -R u+w,a+X ${dataDir}/static_content/
          # Make static_content accessible to nginx
          chmod o+X ${dataDir}

          ${pkg}/bin/sympa.pl --health_check
        '';
      };
      systemd.services.sympa-archive = {
        description = "Sympa mailing list manager (archiving)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = sympaServiceConfig "archived";
      };
      systemd.services.sympa-bounce = {
        description = "Sympa mailing list manager (bounce processing)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = sympaServiceConfig "bounced";
      };
      systemd.services.sympa-bulk = {
        description = "Sympa mailing list manager (message distribution)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = sympaServiceConfig "bulk";
      };
      systemd.services.sympa-task = {
        description = "Sympa mailing list manager (task management)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = sympaServiceConfig "task_manager";
      };
    }

    (mkIf cfg.web.enable {
      systemd.services.wwsympa = {
        wantedBy = [ "multi-user.target" ];
        after = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = {
          Type = "forking";
          Restart = "always";
          ExecStart = ''${pkgs.spawn_fcgi}/bin/spawn-fcgi \
            -u ${user} \
            -g ${group} \
            -U nginx \
            -M 0600 \
            -F ${toString cfg.web.fcgiProcs} \
            -P /run/sympa/wwsympa.pid \
            -s /run/sympa/wwsympa.socket \
            ${pkg}/bin/wwsympa.fcgi
          '';
          PIDFile = "/run/sympa/wwsympa.pid";
        };
      };
    })

    (mkIf (cfg.web.enable && cfg.web.server == "nginx") {
      services.nginx.enable = true;

      services.nginx.virtualHosts = let
        vHosts = unique (remove null (mapAttrsToList (_k: v: v.webHost) cfg.domains));
        hostLocations = host: mapAttrsToList (_k: v: v.webLocation) (filterAttrs (_k: v: v.webHost == host) cfg.domains);
        httpsOpts = optionalAttrs cfg.web.https { forceSSL = mkDefault true; enableACME = mkDefault true; };
      in
      genAttrs vHosts (host: {
        locations = genAttrs (hostLocations host) (loc: {
          extraConfig = ''
            include ${pkgs.nginx}/conf/fastcgi_params;

            fastcgi_pass unix:/run/sympa/wwsympa.socket;
            fastcgi_split_path_info ^(${loc})(.*)$;

            fastcgi_param PATH_INFO       $fastcgi_path_info;
            fastcgi_param SCRIPT_FILENAME ${pkg}/bin/wwsympa.fcgi;
          '';
        }) // {
          "/static-sympa/".alias = "${dataDir}/static_content/";
        };
      } // httpsOpts);
    })

    (mkIf (cfg.mta.type == "postfix") {
      services.postfix = {
        enable = true;
        recipientDelimiter = "+";
        config = {
          virtual_alias_maps = [ "hash:${dataDir}/virtual.sympa" ];
          virtual_mailbox_maps = [
            "hash:${dataDir}/transport.sympa"
            "hash:${dataDir}/sympa_transport"
            "hash:${dataDir}/virtual.sympa"
          ];
          virtual_mailbox_domains = [ "hash:${dataDir}/transport.sympa" ];
          transport_maps = [
            "hash:${dataDir}/transport.sympa"
            "hash:${dataDir}/sympa_transport"
          ];
        };
        masterConfig = {
          "sympa" = {
            type = "unix";
            privileged = true;
            chroot = false;
            command = "pipe";
            args = [
              "flags=hqRu"
              "user=${user}"
              "argv=${pkg}/bin/queue"
              "\${nexthop}"
            ];
          };
          "sympabounce" = {
            type = "unix";
            privileged = true;
            chroot = false;
            command = "pipe";
            args = [
              "flags=hqRu"
              "user=${user}"
              "argv=${pkg}/bin/bouncequeue"
              "\${nexthop}"
            ];
          };
        };
      };
    })

  ]);
}
