{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "autoremove-torrents";
  version = "1.5.5";

  src = fetchFromGitHub {
    owner = "jerrymakesjelly";
    repo = "autoremove-torrents";
    rev = "v${version}";
    hash = "sha256-OXvglXzzFuI8nDdKYNWBL2L+9rMv6d1ggvtUwN6NkQk=";
  };

  propagatedBuildInputs = with python3Packages; [
    requests
    pyyaml
    deluge-client
  ];

  # No tests in the repository
  doCheck = false;

  meta = with lib; {
    description = "Automatically remove torrents based on your strategies";
    homepage = "https://github.com/jerrymakesjelly/autoremove-torrents";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "autoremove-torrents";
  };
}
