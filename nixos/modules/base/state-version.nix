{
  config,
  ...
}:
{
  system.stateVersion = config.lib.self.flakeStateVersion;
}
