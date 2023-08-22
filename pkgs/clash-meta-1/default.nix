{
  buildGoModule,
  source,
}:
buildGoModule rec {
  inherit (source) pname version src vendorSha256;

  # Do not build testing suit
  excludedPackages = ["./test"];

  CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/Dreamacro/clash/constant.Version=dev-${version}"
    "-X github.com/Dreamacro/clash/constant.BuildTime=${version}"
  ];

  tags = [
    "with_gvisor"
  ];

  # Network required
  doCheck = false;

  postInstall = ''
    mv $out/bin/clash $out/bin/clash-meta
  '';
}
