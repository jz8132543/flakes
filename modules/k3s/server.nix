{ config, ... } :

{
  services = {
    k3s = {
      enable = true;
      role = "server";
      # tokenFile = config.sops.secrets.k3s-server-token.path;
      extraFlags = toString [
      # "--kubelet-arg=v=4" # Optionally add additional args to k3s
      # "--kubelet-arg=cgroup-driver=systemd"
      # "--container-runtime-endpoint unix:///run/containerd/containerd.sock"
      "--disable traefik"
      "--https-listen-port 6444"
      ];
    };
  };
}
