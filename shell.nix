with import <nixpkgs> {}; {
  env = stdenv.mkDerivation {
    name = "realwallpaper";
    buildInputs = [
      xplanet
      imagemagick
      curl
      file
      jq
    ];
    SSL_CERT_FILE="/etc/ssl/certs/ca-bundle.crt";
  };
}
