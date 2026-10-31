{
  "proxy.config.admin.user_id" = "trafficserver";
  "proxy.config.body_factory.template_sets_dir" = "/etc/trafficserver/body_factory";
  "proxy.config.cache.ram_cache.algorithm" = 1;
  # Keep the shared edge profile usable on sub-1GiB nodes.
  "proxy.config.cache.ram_cache.size" = 33554432;
  "proxy.config.exec_thread.autoconfig" = 1;
  "proxy.config.http.cache.cache_responses_to_cookies" = 1;
  "proxy.config.http.cache.required_headers" = 0;
  "proxy.config.http.server_ports" = "8089";
  "proxy.config.log.logging_enabled" = 3;
  "proxy.config.net.connections_throttle" = 10000;
  "proxy.config.net.listen_backlog" = 512;
  "proxy.config.url_remap.pristine_host_hdr" = 1;
}
