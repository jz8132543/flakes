{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "trafficcontrol";
  version = "8.0.2";

  src = fetchFromGitHub {
    owner = "apache";
    repo = "trafficcontrol";
    rev = "v${version}";
    sha256 = "1xcfd9g6zd9yli73pxsy98qdnilxpiwp5ar6hakyavjykg6kcpl6";
  };

  # Upstream release tarball contains complete vendor/ tree
  vendorHash = null;

  subPackages = [
    "cache-config/t3c"
    "cache-config/t3c-apply"
    "cache-config/t3c-check-reload"
    "cache-config/t3c-diff"
    "cache-config/t3c-generate"
    "cache-config/t3c-preprocess"
    "cache-config/t3c-request"
    "cache-config/t3c-update"
    "traffic_ops/traffic_ops_golang"
    "traffic_monitor"
  ];

  ldflags = [
    "-X main.Version=${version}"
    "-s"
    "-w"
  ];

  doCheck = false;

  meta = with lib; {
    description = "Apache Traffic Control - Open source CDN management suite (t3c, Traffic Ops, Traffic Monitor)";
    homepage = "https://trafficcontrol.apache.org/";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
