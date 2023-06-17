# This file was generated by nvfetcher, please do not modify it manually.
{ fetchgit, fetchurl, fetchFromGitHub, dockerTools }:
{
  fedibird-fe = {
    pname = "fedibird-fe";
    version = "9e331f8b9be690942d45f3c870b6a1bdb8ab47df";
    src = fetchurl {
      url = "https://akkoma-updates.s3-website.fr-par.scw.cloud/frontend/akkoma/fedibird-fe.zip";
      sha256 = "sha256-DcL8TvfWxPp60IrkS3fbcW0ZlAmmvxAL7n+joLgXukg=";
    };
    date = "2023-03-08";
  };
  masto-fe = {
    pname = "masto-fe";
    version = "0a6462682a706f04c5daa4a18f1fd78b307706b2";
    src = fetchurl {
      url = "https://akkoma-updates.s3-website.fr-par.scw.cloud/frontend/akkoma/masto-fe.zip";
      sha256 = "sha256-fpDGSxjOdjvtWQveYcG2KmD9+SfxB8iUWix70YMeSQI=";
    };
    date = "2023-04-14";
  };
  pleroma-fe = {
    pname = "pleroma-fe";
    version = "42ffce97d614a6157a4d20ff5de32c4ff94c9293";
    src = fetchurl {
      url = "https://akkoma-updates.s3-website.fr-par.scw.cloud/frontend/stable/akkoma-fe.zip";
      sha256 = "sha256-t81mKWUdbjmp6DxHWcnG5cS4yyJ3CulWWZDYamk5Ahw=";
    };
    date = "2023-05-23";
  };
  soapbox = {
    pname = "soapbox";
    version = "v3.2.0";
    src = fetchurl {
      url = "https://gitlab.com/soapbox-pub/soapbox/-/jobs/artifacts/v3.2.0/download?job=build-production";
      sha256 = "sha256-AdW6JK7JkIKLZ8X+N9STeOHqmGNUdhcXyC9jsQPTa9o=";
    };
  };
  swagger-ui = {
    pname = "swagger-ui";
    version = "112baeca6b20fc8ffd30421fc27c2024af858a6c";
    src = fetchurl {
      url = "https://akkoma-updates.s3-website.fr-par.scw.cloud/frontend/swagger-ui.zip";
      sha256 = "sha256-OPeQZFnhRCkZMmawG4AcXV+/dMUy8vNOGgEXV07tg64=";
    };
    date = "2023-06-16";
  };
}
