{
  configurations,
  self,
  lib,
}:
let
  augmented = self // {
    hostNames = self.hostNames ++ [ "inventory-test-invalid-host" ];
    nixosConfigurations = configurations // {
      inventory-test-invalid-host = throw "An existing system evaluated another host's configuration.";
    };
  };
  sshArtifacts =
    host:
    let
      cfg = host.config;
      home = cfg.home-manager.users.tippy or null;
    in
    {
      nativeClient = cfg.programs.ssh.package.drvPath;
      nativeServer = cfg.services.openssh.package.drvPath;
      udpServer = cfg.programs.ssh.transport.package.drvPath;
      clientConfig = toString cfg.environment.etc."ssh/ssh_config".source;
      serverConfig = toString cfg.environment.etc."ssh/sshd_config".source;
      homeConfig = if home == null then null else toString home.home.file.".ssh/config".source;
    };
  results = lib.mapAttrs (
    _: original:
    let
      control = original.extendModules { specialArgs.self = self; };
      changed = original.extendModules { specialArgs.self = augmented; };
    in
    {
      ssh = sshArtifacts original == sshArtifacts changed;
      control =
        original.config.system.build.toplevel.drvPath == control.config.system.build.toplevel.drvPath;
      system =
        control.config.system.build.toplevel.drvPath == changed.config.system.build.toplevel.drvPath;
    }
  ) configurations;
in
{
  hostsChecked = builtins.length (builtins.attrNames results);
  sshArtifactsUnchanged = lib.all (r: r.ssh) (builtins.attrValues results);
  extensionControlUnchanged = lib.all (r: r.control) (builtins.attrValues results);
  systemToplevelsUnchanged = lib.all (r: r.system) (builtins.attrValues results);
}
