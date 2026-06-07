# 只将源代码暴露到 Nix store，供 podman build 使用
{
  fetchFromGitHub,
  lib,
  pkgs,
  ...
}:
let
  version = "93129e163377f0ce292471c6f202f8eaf40106d1";
  src = fetchFromGitHub {
    owner = "VJBots";
    repo = "VJ-Save-Restricted-Content";
    rev = version;
    fetchSubmodules = false;
    sha256 = "sha256-Tfb3RLkH+CLSlUQDxzzf91ZK/zNFuMLiz3RjA5yyvUI=";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "save-restricted-content-bot";
  inherit version src;
  dontBuild = true;
  installPhase = ''
        cp -r . $out
        if [ ! -f "$out/Dockerfile" ]; then
          cat > "$out/Dockerfile" <<'EOF'
    FROM python:3.10-slim

    # Install system dependencies
    RUN apt-get update && apt-get install -y \
        git \
        ffmpeg \
        libsm6 \
        libxext6 \
        && rm -rf /var/lib/apt/lists/*

    WORKDIR /app

    # Copy requirements and install
    COPY requirements.txt .
    RUN pip3 install --no-cache-dir -U pip && \
        pip3 install --no-cache-dir -U -r requirements.txt

    # Copy application code
    COPY . .

    CMD ["python3", "main.py"]
    EOF
        fi
  '';
  meta = with lib; {
    description = "Save Restricted Content Bot v3 — source for container build";
    homepage = "https://github.com/VJBots/VJ-Save-Restricted-Content";
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
