{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.sympa;
  user = cfg.user;
  group = cfg.group;

  sympaSubServices = [
    "sympa-archive.service"
    "sympa-bounce.service"
    "sympa-bulk.service"
    "sympa-task.service"
  ];

  mainConfig = pkgs.writeText "sympa.conf" ''
    domain      ${cfg.domain}
    listmaster  ${concatStringsSep "," cfg.listMasters}
    lang        ${cfg.lang}

    home /srv/sympa/list_data

    db_type ${cfg.database.type}
    db_name ${cfg.database.name}
    ${optionalString (cfg.database.host != null) "db_host ${cfg.database.host}"}
    ${optionalString (cfg.database.port != null) "db_port ${cfg.database.port}"}
    ${optionalString (cfg.database.user != null) "db_user ${cfg.database.user}"}
    ${optionalString (cfg.database.password != null) "db_passwd ${cfg.database.password}"}

    sendmail /run/wrappers/bin/sendmail
    sendmail_aliases /srv/sympa/sympa_transport

    aliases_program ${pkgs.postfix}/bin/postmap
    aliases_db_type hash

    # WEB
    wwsympa_url ${cfg.web.url}
    static_content_path /srv/sympa/static_content
    css_path            /srv/sympa/static_content/css
    pictures_path       /srv/sympa/static_content/pictures
    mhonarc ${pkgs.perlPackages.MHonArc}/bin/mhonarc

    ${cfg.extraConfig}
  '';

  virtDomains = unique (cfg.virtualDomains);

  transport = pkgs.writeText "transport.sympa" (concatStringsSep "\n" (flip map virtDomains (domain: ''
    ${domain}                        error:User unknown in recipient table
    sympa@${domain}                  sympa:sympa@${domain}
    listmaster@${domain}             sympa:listmaster@${domain}
    bounce@${domain}                 sympabounce:sympa@${domain}
    abuse-feedback-report@${domain}  sympabounce:sympa@${domain}
  '')));

  virtual = pkgs.writeText "virtual.sympa" (concatStringsSep "\n" (flip map virtDomains (domain: ''
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

  listModule = { ... }: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Name of the mailinglist";
      };
      domain = mkOption {
        type = types.str;
        description = "Domain of the mailinglist";
      };
    };
  };
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

      domain = mkOption {
        type = types.str;
        description = ''
          FQDN of the mailinglist server.
        '';
        example = "sympa.example.org";
      };

      virtualDomains = mkOption {
        type = types.listOf types.str;
        example = [
          "sympa.example.org"
          "lists.example.org"
        ];

        description = "Virtual domains handled by this instances";
      };

      listMasters = mkOption {
        type = types.listOf types.str;
        example = [ "postmaster@sympa.example.org" ];
        description = ''
          The list of the email addresses of the listmasters
          (users authorized to perform global server commands).
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
          default = if cfg.database.type == "SQLite" then "/srv/sympa/sympa.sqlite" else "sympa";
          description = "Database name. When using SQLite this must be an absolute path to the database file.";
        };

        user = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Database user.";
        };

        password = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Database password. Warning: this is stored in cleartext in the Nix store!";
        };

        #passwordFile = mkOption {}; #TODO
      };

      web = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable Sympa web interface.";
        };
        url = mkOption {
          type = types.str;
          example = "http://sympa.example.org/sympa";
          description = "URL of the Sympa web interface.";
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
        systemPackages = [ pkgs.sympa ];
      };

      users.users = optional (user == "sympa")
        { name = "sympa";
          description = "Sympa mailing list manager user";
          uid = config.ids.uids.sympa;
          group = group;
        };

      users.groups =
        optional (group == "sympa")
        { name = group;
          gid = config.ids.gids.sympa;
        };


      services.postfix = {
        # XXX: ?? proly not
        enable = true;
        recipientDelimiter = "+";
        config = {
          virtual_alias_maps = [ "hash:/srv/sympa/virtual.sympa" ];
          virtual_mailbox_maps = [
            "hash:/srv/sympa/transport.sympa"
            "hash:/srv/sympa/sympa_transport"
            "hash:/srv/sympa/virtual.sympa"
          ];
          virtual_mailbox_domains = [ "hash:/srv/sympa/transport.sympa" ];
          transport_maps = [
            "hash:/srv/sympa/transport.sympa"
            "hash:/srv/sympa/sympa_transport"
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
              "argv=${pkgs.sympa}/bin/queue"
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
              "argv=${pkgs.sympa}/bin/bouncequeue"
              "\${nexthop}"
            ];
          };
        };
      };

      # XXX: ?? proly not, mkIf sympa.(nginx, postfix).enable?
      services.nginx.enable = true;

      services.nginx.virtualHosts = {
        "${cfg.domain}" = {
          locations."/sympa".extraConfig = ''
            fastcgi_pass unix:/run/sympa/wwsympa.socket;
            fastcgi_split_path_info ^(/sympa)(.*)$;

            fastcgi_param PATH_INFO          $fastcgi_path_info;
            fastcgi_param SCRIPT_FILENAME    ${pkgs.sympa}/bin/wwsympa.fcgi;
            fastcgi_param QUERY_STRING       $query_string;
            fastcgi_param REQUEST_METHOD     $request_method;
            fastcgi_param CONTENT_TYPE       $content_type;
            fastcgi_param CONTENT_LENGTH     $content_length;
            fastcgi_param PATH_INFO          $fastcgi_path_info;
            fastcgi_param SCRIPT_NAME        $fastcgi_script_name;
            fastcgi_param REQUEST_URI        $request_uri;
            fastcgi_param DOCUMENT_URI       $document_uri;
            fastcgi_param DOCUMENT_ROOT      $document_root;
            fastcgi_param SERVER_PROTOCOL    $server_protocol;
            fastcgi_param GATEWAY_INTERFACE  CGI/1.1;
            fastcgi_param SERVER_SOFTWARE    nginx;
            fastcgi_param REMOTE_ADDR        $remote_addr;
            fastcgi_param REMOTE_PORT        $remote_port;
            fastcgi_param SERVER_ADDR        $server_addr;
            fastcgi_param SERVER_PORT        $server_port;
            fastcgi_param SERVER_NAME        $host;
          '';

          locations."/static-sympa/".alias = "/srv/sympa/static_content/";
        };
      };

      systemd.tmpfiles.rules = [
        "d '/run/sympa' 0755 ${user} ${group} - -"
      ];

      systemd.services.sympa = {
        description = "Sympa mailing list manager";

        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = [ pkgs.sympa ];
        wants = sympaSubServices;
        before = sympaSubServices;

        serviceConfig = {
          Type = "forking";
          Restart = "always";
          ExecStart = "${pkgs.sympa}/bin/sympa_msg.pl";
          PIDFile = "/run/sympa/sympa_msg.pid";
        };

        preStart = ''
          mkdir -p /srv/sympa/spool
          mkdir -p /srv/sympa/list_data
          cp ${mainConfig} /srv/sympa/sympa.conf

          ${concatStringsSep "\n" (flip map virtDomains (domain:
          ''
            mkdir -p -m 750 /srv/sympa/${domain}
            touch /srv/sympa/${domain}/robot.conf
            mkdir -p -m 750 /srv/sympa/list_data/${domain}
          ''))}

          cp ${virtual} /srv/sympa/virtual.sympa
          cp ${transport} /srv/sympa/transport.sympa
          cp ${listAliases} /srv/sympa/list_aliases.tt2

          touch /srv/sympa/sympa_transport

          ${pkgs.postfix}/bin/postmap hash:/srv/sympa/virtual.sympa
          ${pkgs.postfix}/bin/postmap hash:/srv/sympa/transport.sympa
          ${pkgs.sympa}/bin/sympa_newaliases.pl


          cp -a ${pkgs.sympa}/static_content /srv/sympa/
          # Yes, wwsympa needs write access to static_content..
          chmod -R 755 /srv/sympa/static_content/css/


          chown -R ${user}:${group} /srv/sympa
          ${pkgs.sympa}/bin/sympa.pl --health_check
        '';
      };
      systemd.services.sympa-archive = {
        description = "Sympa mailing list manager (archiving)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = {
          Type = "forking";
          Restart = "always";
          ExecStart = "${pkgs.sympa}/bin/archived.pl";
          PIDFile = "/run/sympa/archived.pid";
        };
      };
      systemd.services.sympa-bounce = {
        description = "Sympa mailing list manager (bounce processing)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = {
          Type = "forking";
          Restart = "always";
          ExecStart = "${pkgs.sympa}/bin/bounced.pl";
          PIDFile = "/run/sympa/bounced.pid";
        };
      };
      systemd.services.sympa-bulk = {
        description = "Sympa mailing list manager (message distribution)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = {
          Type = "forking";
          Restart = "always";
          ExecStart = "${pkgs.sympa}/bin/bulk.pl";
          PIDFile = "/run/sympa/bulk.pid";
        };
      };
      systemd.services.sympa-task = {
        description = "Sympa mailing list manager (task management)";
        bindsTo = [ "sympa.service" ];
        restartTriggers = [ mainConfig ];
        serviceConfig = {
          Type = "forking";
          Restart = "always";
          ExecStart = "${pkgs.sympa}/bin/task_manager.pl";
          PIDFile = "/run/sympa/task_manager.pid";
        };
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
            -F 5 \
            -P /run/sympa/wwsympa.pid \
            -s /run/sympa/wwsympa.socket \
            ${pkgs.sympa}/bin/wwsympa.fcgi
          '';
          PIDFile = "/run/sympa/wwsympa.pid";
        };
      };
    })
  ]);
}
