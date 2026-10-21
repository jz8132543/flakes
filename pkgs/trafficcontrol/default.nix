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

  outputs = [
    "out"
    "t3c"
  ];

  postInstall = ''
    # Ensure t3c binary exists
    if [ ! -f "$out/bin/t3c" ]; then
      echo "Error: t3c binary not found in $out/bin" >&2
      exit 1
    fi

    # Support traffic_control/install_dir/bin/t3c path expectation
    mkdir -p "$out/traffic_control/install_dir/bin"
    ln -sf "$out/bin/t3c" "$out/traffic_control/install_dir/bin/t3c"

    # Export lightweight t3c output containing only edge t3c client binaries
    mkdir -p "$t3c/bin"
    cp -a "$out/bin"/t3c* "$t3c/bin/"
  '';

  passthru = {
    inherit version;
  };

  doCheck = false;

  meta = with lib; {
    description = "Apache Traffic Control - Open source CDN management suite (t3c, Traffic Ops, Traffic Monitor)";
    homepage = "https://trafficcontrol.apache.org/";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
