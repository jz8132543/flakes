{
  lib,
  pkgs,
  python3Packages,
  source,
  calibre,
  makeWrapper,
}:
let
  epub_meta =
    let
      pname = "epub_meta";
      version = "0.0.7";
    in
    pkgs.python3Packages.buildPythonPackage {
      inherit pname version;
      src = pkgs.fetchFromGitHub {
        owner = "paulocheque";
        repo = "epub-meta";
        rev = "3cbbe936d97ec9b78918f6a4f4c8d4d3c89c29c6";
        sha256 = "sha256-Wor0sDLaNbPa+D3tcDfX208vRvEBDha4deCJOUkDU2I=";
      };
      doCheck = false;
      pyproject = true;
      "build-system" = [ python3Packages.setuptools ];
    };
in
python3Packages.buildPythonApplication {
  inherit (source) pname version src;

  # # Build epub_meta from upstream GitHub (not present in nixpkgs)
  # epub_meta = python3Packages.buildPythonPackage {
  #   pname = "epub_meta";
  #   version = "0.0.7";
  #   src = fetchFromGitHub {
  #     owner = "paulocheque";
  #     repo = "epub-meta";
  #     rev = "3cbbe936d97ec9b78918f6a4f4c8d4d3c89c29c6";
  #     sha256 = "sha256-Wor0sDLaNbPa+D3tcDfX208vRvEBDha4deCJOUkDU2I=";
  #   };
  #   doCheck = false;
  #   pyproject = true;
  #   "build-system" = [ python3Packages.setuptools ];
  # };

  propagatedBuildInputs = with python3Packages; [
    configparser
    urllib3
    python3Packages."validate-email"
    ebooklib
    epub_meta
    pika
    weasyprint
    python3Packages."python-i18n"
    dnspython
    pytelegrambotapi
    redis
    requests
    beautifulsoup4
    flask
  ];

  nativeBuildInputs = [
    makeWrapper
    python3Packages.pip
    python3Packages.setuptools
    python3Packages.wheel
  ];

  postPatch = ''
        substituteInPlace bot.py --replace "'python3', 'loop_upload_action.py'" "sys.executable, 'loop_upload_action.py'"

        # Patch send.py to use external SMTP from config
        cat >> send.py <<EOF
    def get_smtp():
        host = config.get("SMTP", "HOST", fallback="127.0.0.1")
        port = config.getint("SMTP", "PORT", fallback=25)
        user = config.get("SMTP", "USER", fallback=None)
        password = config.get("SMTP", "PASS", fallback=None)

        if port == 465:
            s = smtplib.SMTP_SSL(host, port)
        else:
            s = smtplib.SMTP(host, port)

        if user and password:
            s.login(user, password)
        return s
    EOF
        substituteInPlace send.py --replace 'smtp = smtplib.SMTP("127.0.0.1")' 'smtp = get_smtp()'

        # Ensure upstream Makefile installs requirements into the build output (only if Makefile exists)
        if [ -f Makefile ]; then
          substituteInPlace Makefile --replace 'pip install -r requirements.txt' "pip install --target \"$out/lib/send2kindlebot\" -r requirements.txt --no-deps --break-system-packages"
        fi
        # Ensure main block is syntactically correct and chooses safe port/ssl usage
        cat > fix_main.py <<'PY'
      from pathlib import Path
      p = Path('bot.py')
      text = p.read_text()
      idx = text.find('if __name__ == "__main__":')
      if idx != -1:
        new = '''if __name__ == "__main__":
        # bot.infinity_polling()
        if CERT and PRIVKEY and os.path.exists(CERT) and os.path.exists(PRIVKEY):
          server.run(host="0.0.0.0", port=443, ssl_context=(CERT, PRIVKEY))
        else:
          server.run(host="0.0.0.0", port=8443)
      '''
        p.write_text(text[:idx] + new)
      PY
        "${python3Packages.python.interpreter}" fix_main.py || true
        # SSL/port handling moved to wrapper script; no source rewrite here
  '';

  buildPhase = ''
        cat > pip <<EOF
    #!/bin/sh
    exec "${python3Packages.python.interpreter}" -m pip "$@" --target "$out/lib/send2kindlebot" --no-deps --break-system-packages
    EOF
        chmod +x pip
        export PATH="$PWD:$PATH"
        if [ -f Makefile ]; then
          make install
        fi
  '';

  format = "other";

  installPhase = ''
      mkdir -p $out/lib/send2kindlebot
      cp -r * $out/lib/send2kindlebot/

      # Create wrappers for the scripts
      mkdir -p $out/bin

      cat > $out/bin/send2kindlebot-bot <<'PY'
    #!${python3Packages.python.interpreter}
    import os
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib", "send2kindlebot"))
    try:
      from bot import server, config
    except Exception:
      from send2kindlebot import bot as b
      server = b.server
      config = b.config

    # Prefer unprivileged port by default to avoid colliding with reverse proxies.
    # Set environment variable FORCE_443=1 to attempt binding to 443.
    CERT = os.environ.get("CERT", "") or config.get("DEFAULT", "CERT", fallback="")
    PRIVKEY = os.environ.get("PRIVKEY", "") or config.get("DEFAULT", "PRIVKEY", fallback="")
    FORCE_443 = os.environ.get("FORCE_443", "").lower() in ("1", "true", "yes")

    # Allow overriding bind address and port from systemd environment
    BIND_ADDR = os.environ.get("BIND_ADDR", "127.0.0.1")
    ENV_PORT = os.environ.get("PORT", "")

    def_try_ports = [443, 8443, 8080, 5000]

    ports = []
    if ENV_PORT:
      try:
        ports = [int(ENV_PORT)] + [p for p in def_try_ports if p != int(ENV_PORT)]
      except Exception:
        ports = def_try_ports
    else:
      if FORCE_443 and CERT and PRIVKEY and os.path.exists(CERT) and os.path.exists(PRIVKEY):
        ports = def_try_ports
      else:
        ports = [p for p in def_try_ports if p != 443]

    for port in ports:
      try:
        if port == 443:
          server.run(host=BIND_ADDR, port=port, ssl_context=(CERT, PRIVKEY))
        else:
          server.run(host=BIND_ADDR, port=port)
        break
      except Exception as e:
        sys.stderr.write(f"port {port} failed: {e}\n")
    else:
      sys.stderr.write("no available port to bind\n")
      raise SystemExit(1)
    PY
      chmod +x $out/bin/send2kindlebot-bot

      makeWrapper ${python3Packages.python.interpreter} $out/bin/send2kindlebot-send \
        --add-flags "$out/lib/send2kindlebot/send.py" \
        --prefix PATH : ${lib.makeBinPath [ calibre ]} \
        --set PYTHONPATH "$PYTHONPATH:$out/lib/send2kindlebot"

      makeWrapper ${python3Packages.python.interpreter} $out/bin/send2kindlebot-create-db \
        --add-flags "$out/lib/send2kindlebot/create_table.py" \
        --set PYTHONPATH "$PYTHONPATH:$out/lib/send2kindlebot"
  '';

  meta = with lib; {
    description = "Telegram Bot that sends documents to Kindle devices";
    homepage = "https://github.com/gabrielrf/send2kindlebot";
    license = licenses.gpl3Only;
  };
}
