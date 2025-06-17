{
  source,
  stdenv,
  pkgs,
}:
let
  pythonEnv = pkgs.python310.withPackages (
    ps: with ps; [
      # peewee
      # python-telegram-bot
      # validate-email
      # pymysql
      # python-i18n
      #
      # requests
      # urllib3
      # configparser
      # pytz
      # tzlocal
    ]
  );
in
pkgs.stdenv.mkDerivation {
  inherit (source) pname version src;
  doConfigure = false;
  doCheck = false;
  allowImportFromDerivation = true;
  buildPhase = ''
    ${pythonEnv}/bin/python -m venv venv
    . venv/bin/activate
    pip3 install --no-cache-dir -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple -r requirements.txt
  '';
  installPhase = ''
    mkdir -p $out
    cp * $out/
  '';
}
