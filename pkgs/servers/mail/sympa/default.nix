{ stdenv, perlPackages, fetchurl, makeWrapper }:

let
  pname = "sympa";
  version = "6.2.44";
in
stdenv.mkDerivation rec {
  name = "${pname}-${version}";

  src = fetchurl {
    url = "https://github.com/sympa-community/${pname}/releases/download/${version}/${pname}-${version}.tar.gz";
    sha256 = "10qzzjpl9vkkh3qlw4z44wmgcf8qlnazncl33xv4fv6wdg2wns2v";
  };

  configureFlags = [
    "--without-initdir"
    "--without-unitsdir"
    "--without-smrshdir"
    "--with-piddir=/run/sympa"
    "--with-spooldir=/srv/sympa/spool"
    "--with-confdir=/srv/sympa"
    "--sysconfdir=/srv/sympa"
  ];
  buildInputs = [ perlPackages.perl makeWrapper ];
  propagatedBuildInputs = with perlPackages; [
    ArchiveZip
    CGI
    CGIFast
    ClassSingleton
    DateTime
    DBI
    DateTimeFormatMail
    DateTimeTimeZone
    DigestMD5
    Encode
    FCGI
    FileCopyRecursive
    FileNFSLock
    FilePath
    HTMLParser
    HTMLFormatter
    HTMLTree
    HTMLStripScriptsParser
    IO
    IOStringy
    LWP
    libintl_perl

    MHonArc
    MIMEBase64
    MIMECharset
    MIMETools
    MIMEEncWords
    MIMELiteHTML
    MailTools
    NetCIDR
    ScalarListUtils
    SysSyslog
    TermProgressBar
    TemplateToolkit
    URI
    UnicodeLineBreak
    XMLLibXML

    ### Features
    Clone
    CryptEksblowfish

    DBDPg
    DBDSQLite
    DBDmysql

    DataPassword
    EncodeLocale
    IOSocketSSL
    MailDKIM
    NetDNS
    NetLDAP
    NetSMTP
    SOAPLite
  ];

  preInstall = ''
    mkdir "$TMP/bin"
    for i in chown chgrp chmod; do
      echo '#!${stdenv.shell}' >> "$TMP/bin/$i"
      chmod +x "$TMP/bin/$i"
      PATH="$TMP/bin:$PATH"
    done
  '';

  postInstall = ''
    rm -rf "$TMP/bin"

    for i in $out/bin/*.pl; do
      wrapProgram "$i" \
        --prefix PERL5LIB : "$PERL5LIB"
    done

    wrapProgram "$out/bin/wwsympa.fcgi" \
      --prefix PERL5LIB : "$PERL5LIB"
  '';

  meta = with stdenv.lib; {
    description = "Sympa is an open source mailing list manager";
    homepage = https://www.sympa.org;
    license = licenses.gpl2;
    maintainers = [ maintainers.srk ];
    platforms = platforms.all;
  };
}
