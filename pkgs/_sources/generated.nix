# This file was generated by nvfetcher, please do not modify it manually.
{
  fetchgit,
  fetchurl,
  fetchFromGitHub,
  dockerTools,
}: {
  clash-meta = {
    pname = "clash-meta";
    version = "f241e1f81a53ffed8283c2fd1ab360ca40083318";
    src = fetchFromGitHub {
      owner = "MetaCubeX";
      repo = "Clash.Meta";
      rev = "f241e1f81a53ffed8283c2fd1ab360ca40083318";
      fetchSubmodules = false;
      sha256 = "sha256-wpO7i1QUuVvNnCZ1YzD5sbF97nJmX2rNM4czvyapuEE=";
    };
    vendorSha256 = "sha256-My/fwa8BgaJcSGKcyyzUExVE0M2fk7rMZtOBW7V5edQ=";
    date = "2023-09-09";
  };
  kitty-catppuccin = {
    pname = "kitty-catppuccin";
    version = "4820b3ef3f4968cf3084b2239ce7d1e99ea04dda";
    src = fetchFromGitHub {
      owner = "catppuccin";
      repo = "kitty";
      rev = "4820b3ef3f4968cf3084b2239ce7d1e99ea04dda";
      fetchSubmodules = false;
      sha256 = "sha256-uZSx+fuzcW//5/FtW98q7G4xRRjJjD5aQMbvJ4cs94U=";
    };
    date = "2023-06-09";
  };
}
