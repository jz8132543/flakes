# This file was generated by nvfetcher, please do not modify it manually.
{
  fetchurl,
  fetchFromGitHub,
  dockerTools,
}:
{
  alacritty-catppuccin = {
    pname = "alacritty-catppuccin";
    version = "f6cb5a5c2b404cdaceaff193b9c52317f62c62f7";
    src = fetchFromGitHub {
      owner = "catppuccin";
      repo = "alacritty";
      rev = "f6cb5a5c2b404cdaceaff193b9c52317f62c62f7";
      fetchSubmodules = false;
      sha256 = "sha256-H8bouVCS46h0DgQ+oYY8JitahQDj0V9p2cOoD4cQX+Q=";
    };
    date = "2024-10-28";
  };
  alist = {
    pname = "alist";
    version = "v3.41.0";
    src = fetchurl {
      url = "https://github.com/alist-org/alist/releases/download/v3.41.0/alist-linux-musl-amd64.tar.gz";
      sha256 = "sha256-r1TtEQwqeKQXSchEc/A4lhyrIdKb+B/BEe3wwNubrTA=";
    };
  };
  clash-webui-yacd-meta = {
    pname = "clash-webui-yacd-meta";
    version = "8753c22b66388f07b64d72c60e5c479b63d15c5a";
    src = fetchurl {
      url = "https://github.com/MetaCubeX/Yacd-meta/archive/8753c22b66388f07b64d72c60e5c479b63d15c5a.zip";
      sha256 = "sha256-3Mvl6KNXNxEWfAnznsWonEUSS5Okq0ChXhECsBAqcUU=";
    };
    date = "2024-08-11";
  };
  kitty-catppuccin = {
    pname = "kitty-catppuccin";
    version = "b14e8385c827f2d41660b71c7fec1e92bdcf2676";
    src = fetchFromGitHub {
      owner = "catppuccin";
      repo = "kitty";
      rev = "b14e8385c827f2d41660b71c7fec1e92bdcf2676";
      fetchSubmodules = false;
      sha256 = "sha256-59ON7CzVgfZUo7F81qQZQ1r6kpcjR3OPvTl99gzDP8E=";
    };
    date = "2024-11-10";
  };
  trackerslist = {
    pname = "trackerslist";
    version = "latest";
    src = fetchurl {
      url = "https://cf.trackerslist.com/best_aria2.txt";
      sha256 = "sha256-iZFCjuW45y9pbzE8Q9QdoUuX5xxXbOY9lpakqJPpti0=";
    };
  };
}
