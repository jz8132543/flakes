# VJBots/VJ-Save-Restricted-Content
# 只将源代码暴露到 Nix store，供 podman build 使用
{
  fetchFromGitHub,
  lib,
  pkgs,
  ...
}:
let
  version = "93129e163377f0ce292471c6f202f8eaf40106d1-p1";
  src = fetchFromGitHub {
    owner = "VJBots";
    repo = "VJ-Save-Restricted-Content";
    rev = "93129e163377f0ce292471c6f202f8eaf40106d1";
    fetchSubmodules = false;
    sha256 = "sha256-Tfb3RLkH+CLSlUQDxzzf91ZK/zNFuMLiz3RjA5yyvUI=";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "save-restricted-content-bot";
  inherit version src;
  nativeBuildInputs = [ pkgs.python3 ];
  dontBuild = true;
  installPhase = ''
        cp -r . $out
        chmod -R u+w $out

        python3 - << 'PYEOF'
    import os, re

    path = os.path.join(os.environ["out"], "TechVJ", "start.py")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    pattern = r'datas = message\.text\.split\("/"\)\s+temp = datas\[-1\]\.replace\("\?single",\s*""\)\.split\("-"\)\s+fromID = int\(temp\[0\]\.strip\(\)\)\s+try:\s+toID = int\(temp\[1\]\.strip\(\)\)\s+except:\s+toID = fromID'

    match = re.search(pattern, content)
    assert match is not None, "Target pattern not found in TechVJ/start.py"

    replacement = """raw_text = message.text.strip()
            tme_idx = raw_text.find("https://t.me/")
            if tme_idx != -1:
                raw_url = raw_text[tme_idx:].split()[0]
            else:
                raw_url = raw_text
            clean_url = raw_url.split("?")[0].split("&")[0].rstrip("/")
            datas = clean_url.split("/")
            temp = datas[-1].split("-")
            try:
                fromID = int(temp[0].strip())
                toID = int(temp[1].strip()) if len(temp) > 1 else fromID
            except Exception:
                return await message.reply_text("**Invalid Link Format.**")"""

    content = content[:match.start()] + replacement + content[match.end():]

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Successfully patched TechVJ/start.py for query parameters and format handling")
    PYEOF

        cat > "$out/Dockerfile" <<'EOF'
    FROM docker.io/library/python:3.10-slim

    # Install system dependencies
    RUN apt-get update && apt-get install -y \
        git \
        ffmpeg \
        libsm6 \
        libxext6 \
        && rm -rf /var/lib/apt/lists/*

    WORKDIR /app

    ENV PYTHONUNBUFFERED=1

    # Copy requirements and install
    COPY requirements.txt .
    RUN pip3 install --no-cache-dir -U pip && \
        pip3 install --no-cache-dir -U -r requirements.txt

    # Copy application code
    COPY . .

    CMD ["python3", "bot.py"]
    EOF
  '';
  meta = with lib; {
    description = "Save Restricted Content Bot — source for container build";
    homepage = "https://github.com/VJBots/VJ-Save-Restricted-Content";
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
