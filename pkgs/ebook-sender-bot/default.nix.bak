{
  lib,
  python3Packages,
  source,
}:
python3Packages.buildPythonPackage rec {
  inherit (source) pname version src;

  buildInputs =
    with python3Packages;
    [
      peewee
      python-telegram-bot
      validate-email
      pymysql
      python-i18n

      requests
      urllib3
      configparser
      pytz
      tzlocal
    ]
    ++ [ pkgs.calibre ];

  # installPhase = ''
  #   tar zxvf $src
  #   mkdir -p "$out"/bin/
  #   install -m 755 openlist -t "$out"/bin/
  # '';

  meta = {
    homepage = "https://github.com/OpenListTeam/OpenList";
    description = "A file list program that supports multiple storage, powered by Gin and Solidjs. / 一个支持多存储的文件列表程序，使用 Gin 和 Solidjs。";
    license = lib.licenses.agpl3Only;
  };
}
