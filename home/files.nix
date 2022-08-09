{ config, pkgs, ... }:

{
  sops.secrets.sshkey = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /key-ssh.keytab;
  };
  sops.secrets.gitkey = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /key-git.keytab;
  };
  home.activation = {
    copySSHKey = dagEntryAfter ["writeBoundary"] ''
      install -D -m600 ${config.sops.secrets.sshkey.path} ${config.home.homeDirectory}/.ssh/id_rsa
  '';
    copyGitKey = dagEntryAfter ["writeBoundary"] ''
      install -D -m600 ${config.sops.secrets.gitkey.path} ${config.home.homeDirectory}/.ssh/id_rsa
  '';
  }
}
