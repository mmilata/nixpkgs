{ buildGoModule
, fetchFromGitHub
, lib
}:

buildGoModule rec {
  pname = "lntop";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "edouardparis";
    repo = "lntop";
    rev = "v${version}";
    sha256 = "08s67s79vq45qnwh62dpd6q27h3kdyq5dwrs240mn833gmgqhcdd";
  };

  vendorSha256 = null;

  meta = with lib; {
    description = "interactive text-mode channels viewer for LND";
    homepage = "https://github.com/edouardparis/lntop";
    license = licenses.mit;
    maintainers = with maintainers; [ mmilata ];
  };
}
