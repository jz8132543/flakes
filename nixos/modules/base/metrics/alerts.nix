{
  lib,
  ...
}:
let
  # 离线告警判定等待时间（服务器/服务重启或维护在此时间内恢复则不报警）
  # 可根据需要自由修改，例如 "10m", "15m", "30m"
  offlineDuration = "10m";

  # 排除的桌面/笔记本主机名正则（不监控其 HostDown 离线状态）
  excludedDesktopHosts = "arx8|surface";
in
{
  options.services.cluster-monitoring.alertRules = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    description = "Alert rules declaration for vmalert";
    default = {
      groups = [
        {
          name = "host_alerts";
          rules = [
            {
              alert = "HostDown";
              expr = ''time() - max_over_time(timestamp(node_time_seconds{instance!~"${excludedDesktopHosts}"})[1h]) > 180'';
              for = offlineDuration;
              labels = {
                severity = "critical";
              };
              annotations = {
                summary = "Host {{ $labels.instance }} is down";
                description = "Host {{ $labels.instance }} heartbeat stopped for more than ${offlineDuration}.";
              };
            }
            {
              alert = "DiskFull";
              expr = ''node_filesystem_free_bytes{mountpoint=~"/|/persist"} / node_filesystem_size_bytes{mountpoint=~"/|/persist"} < 0.10'';
              for = "5m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "Low disk space on {{ $labels.instance }}";
                description = "Disk usage for {{ $labels.mountpoint }} on {{ $labels.instance }} is above 90% (free space under 10%).";
              };
            }
            {
              alert = "DiskFullCritical";
              expr = ''node_filesystem_free_bytes{mountpoint=~"/|/persist"} / node_filesystem_size_bytes{mountpoint=~"/|/persist"} < 0.05'';
              for = "2m";
              labels = {
                severity = "critical";
              };
              annotations = {
                summary = "Critical disk space on {{ $labels.instance }}";
                description = "Disk usage for {{ $labels.mountpoint }} on {{ $labels.instance }} is above 95% (free space under 5%).";
              };
            }
            {
              alert = "MemoryExhausted";
              expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.08";
              for = "5m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "Memory exhausted on {{ $labels.instance }}";
                description = "Available memory on {{ $labels.instance }} is below 8%.";
              };
            }
            {
              alert = "SystemdUnitFailed";
              expr = ''node_systemd_unit_state{state="failed"} > 0'';
              for = "5m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "Systemd unit failed on {{ $labels.instance }}";
                description = "Systemd service {{ $labels.name }} on {{ $labels.instance }} is in failed state.";
              };
            }
          ];
        }
        {
          name = "application_alerts";
          rules = [
            {
              alert = "ServiceHttpDown";
              expr = "probe_success == 0";
              for = offlineDuration;
              labels = {
                severity = "critical";
              };
              annotations = {
                summary = "Service HTTP probe failed for {{ $labels.instance }}";
                description = "Blackbox probe_success == 0 for {{ $labels.instance }} for more than ${offlineDuration}.";
              };
            }
            {
              alert = "SSLCertExpiringSoon";
              expr = "probe_ssl_earliest_cert_expiry - time() < 86400 * 14";
              for = "1h";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "SSL certificate expiring soon for {{ $labels.instance }}";
                description = "SSL certificate for {{ $labels.instance }} expires in less than 14 days.";
              };
            }
            {
              alert = "SSLCertExpiringCritical";
              expr = "probe_ssl_earliest_cert_expiry - time() < 86400 * 3";
              for = "10m";
              labels = {
                severity = "critical";
              };
              annotations = {
                summary = "SSL certificate expiring critically soon for {{ $labels.instance }}";
                description = "SSL certificate for {{ $labels.instance }} expires in less than 3 days.";
              };
            }
            {
              alert = "DatabaseConnectionHigh";
              expr = "pg_stat_activity_count / pg_settings_max_connections > 0.85";
              for = "5m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "PostgreSQL connections near limit on {{ $labels.instance }}";
                description = "PostgreSQL connection pool usage is above 85% on {{ $labels.instance }}.";
              };
            }
          ];
        }
      ];
    };
  };
}
