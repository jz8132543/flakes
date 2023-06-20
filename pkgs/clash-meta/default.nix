{pkgs}:
pkgs.via.overrideAttrs (old: rec {
  vendorSha256 = "sha256-lMeJ3z/iTHIbJI5kTzkQjNPMv5tGMJK/+PM36BUlpjE=";
})
