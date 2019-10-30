{ fetchurl }:

rec {
  major = "6";
  minor = "3";
  patch = "2";
  tweak = "2";

  subdir = "${major}.${minor}.${patch}";

  version = "${subdir}${if tweak == "" then "" else "."}${tweak}";

  src = fetchurl {
    url = "https://download.documentfoundation.org/libreoffice/src/${subdir}/libreoffice-${version}.tar.xz";
    sha256 = "0xdx0zxzg7r3kvch5r83jpaxz389fdr17ix9lvnqn3pi31xs4za0";
  };
}
