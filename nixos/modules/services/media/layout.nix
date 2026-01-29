{
  ...
}:
{
  # Unified Media Layout
  # - /var/lib/data/torrents  (Downloads)
  # - /var/lib/data/media     (Library)
  systemd.tmpfiles.rules = [
    "d /var/lib/data 0775 root media - -"
    "Z /var/lib/data/torrents 0775 qbit media - -"
    "Z /var/lib/data/media 0775 jellyfin media - -"
  ];

  # Ensure the media group exists (also defined in arr.nix, but safe to repeat or ensure order)
  users.groups.media = { };
}
