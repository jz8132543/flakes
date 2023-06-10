{...}: {
  programs.ssh = {
    extraConfig = ''
      CanonicalDomains dora.im ts.dora.im
      CanonicalizeHostname yes
      LogLevel ERROR
      StrictHostKeyChecking no
      Match canonical final Host *.dora.im,*.ts.dora.im
        Port 1022
        HashKnownHosts no
        UserKnownHostsFile /dev/null
    '';
  };
}
