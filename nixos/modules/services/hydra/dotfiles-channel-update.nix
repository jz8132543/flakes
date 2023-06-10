{
  config,
  lib,
  pkgs,
  ...
}: {
  systemd.services."dotfiles-channel-update@" = {
    script = ''
      cd "$STATE_DIRECTORY"

      update_file="$1"
      echo "update_file = $update_file"

      host=$(jq -r '.host' "$update_file")
      echo "host = $host"
      commit=$(jq -r '.commit' "$update_file")
      echo "commit = $commit"
      out=$(jq -r '.out' "$update_file")
      echo "out = $out"

      target_branch="nixos-tested-$host"
      echo "target_branch = $target_branch"

      (
        echo "wait for lock"
        flock 200
        echo "enter critical section"

        systemctl start "copy-cache-dora-im@$(systemd-escape "$out").service"

        # update channel
        if [ ! -d dotfiles ]; then
          git clone https://github.com/jz8132543/flakes.git
          pushd dotfiles
          token=$(cat "$CREDENTIALS_DIRECTORY/github-token")
          git remote set-url origin "https://jz8132543:$token@github.com/jz8132543/flakes.git"
          popd
        fi
        cd dotfiles
        git checkout "$target_branch" || git checkout -b "$target_branch"
        git pull origin "$target_branch" || true
        git fetch
        git merge --ff-only "$commit"
        git push --set-upstream origin "$target_branch"
      dotfiles/$target_branch

      $(git show HEAD --no-patch)
      EOF
      ) 200>/var/lib/dotfiles-channel-update/lock
    '';
    scriptArgs = "%I";
    path = with pkgs; [
      git
      jq
      config.nix.package
      util-linux
    ];
    serviceConfig = {
      User = "hydra";
      Group = "hydra";
      Type = "oneshot";
      StateDirectory = "dotfiles-channel-update";
      Restart = "on-failure";
      LoadCredential = [
        "github-token:${config.sops.secrets."hydra/github-token".path}"
      ];
    };
  };
  sops.secrets."hydra/github-token" = {};

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          RegExp('dotfiles-channel-update@.+\.service|copy-cache-dora-im@.+\.service').test(action.lookup("unit")) === true &&
          subject.isInGroup("hydra")) {
        return polkit.Result.YES;
      }
    });
  '';
}
