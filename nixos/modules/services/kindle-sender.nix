{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.podman
  ];
  virtualisation.oci-containers.containers = {
    kindle-sender = {
      image = "qcgzxw/ebook-sender-bot";
      # entrypoint = null;
      # cmd = [
      #   "/bin/sh"
      #   "-c"
      #   # "/usr/bin/apt update && /usr/bin/apt-get install -y -q apt-utils dialog && echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && /usr/bin/apt-get install -y -q faketime && /usr/bin/faketime -f '-3600d' /usr/bin/tini -- java -jar /app/bin/reader.jar"
      #   "sed -i 's/focal/jammy/g' /etc/apt/sources.list && /usr/bin/apt update && apt upgrade -y && /usr/bin/apt-get install -y -q apt-utils dialog && echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && /usr/bin/apt-get install -y -q faketime && /usr/bin/faketime -f '-3600d' java -jar /app/bin/reader.jar"
      # ];
      environmentFiles = [ config.sops.templates."kindle-sender".path ];
      volumes = [
        "/var/lib/kindle-sender/kindle-sender.log:/app/default.log:rw"
        "/var/lib/kindle-sender/:/app/storage/:rw"
        # "${./kindle-sender-user.py}:/app/app/model/user.py:ro"
      ];
      log-driver = "journald";
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/kindle-sender 0755 root root -"
    "f /var/lib/kindle-sender/kindle-sender.log 0644 root root -"
  ];
  sops.secrets = {
    "kindle-sender/username" = { };
    "kindle-sender/password" = { };
    "kindle-sender/token" = { };
    "kindle-sender/chat-id" = { };
  };
  sops.templates."kindle-sender" = {
    content = ''
      TZ=Asia/Shanghai
      APP_MODE=dev
      MAX_SEND_LIMIT=1
      FORMAT=epub
      EMAIL_PROVIDER=config
      SMTP_HOST=glacier.mxrouting.net
      SMTP_PORT=465
      SMTP_USERNAME=${config.sops.placeholder."kindle-sender/username"}
      SMTP_PASSWORD=${config.sops.placeholder."kindle-sender/password"}
      BOT_TOKEN=${config.sops.placeholder."kindle-sender/token"}
      DEVELOPER_CHAT_ID=${config.sops.placeholder."kindle-sender/chat-id"}
      DB=sqlite
      DB_NAME=storage/database.db
      #DB_HOST=${PG}
      #DB_PORT=5432
      #DB_USER=kindle_sender
      #DB_PASSWORD=""
    '';
  };
}
