{ pkgs, ... }: {

  security.sudo.wheelNeedsPassword = false;
  users = {
    mutableUsers = false;
    users = {
      tippy = {
        isNormalUser = true;
        home  = "/home/tippy";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCv8JCnlVW9uhKcAi649elGFANFaFzzoGfmFzMqjNNh55yLo19XZCshMsUL2+85oz/+Mw4zt/wVsFcEtulrT/O5PUaVZzGoHaeeGcVQZsI85j3OeXJtZDnjO2Y3qZfbWVRZ4V9DisjnwL+bzSgpc14htY56AHo1+WaXTcYuf1pGLseldZwbhg+QCzVVWRw2ZXFE3q62Jvtip16fC0su+U5YtTIkanrvcHRruAgq3PdOlHo/9nDxw66Kf1m+HggHTVCHuCJI/+gCYc0nLc1qpJL5v3hgEn+laVr3Us+AkkAEVPZdgZEtZYxSmj1LpSajsnFmH9goJOBQHHxEsff3Wdd528SLhGAILSYemKgA7nL0zOSPTCk3mEORlSdwmFITiNGUrJ1WueGAZsxfrnbwmAIYMnEiAj/+1MmcySk8upAFYyjhJ5cYYphNJohIbrWd/Bgwpr3Qp/Tb/l3sQVKqELmpej41YDVm/T+4bvz3BHXv9CIBrNJPYLIspqZJiQcBmKM= tippy@DESKTOP-PMU48VM" ];
	      shell = pkgs.zsh;
      };
      root.openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCv8JCnlVW9uhKcAi649elGFANFaFzzoGfmFzMqjNNh55yLo19XZCshMsUL2+85oz/+Mw4zt/wVsFcEtulrT/O5PUaVZzGoHaeeGcVQZsI85j3OeXJtZDnjO2Y3qZfbWVRZ4V9DisjnwL+bzSgpc14htY56AHo1+WaXTcYuf1pGLseldZwbhg+QCzVVWRw2ZXFE3q62Jvtip16fC0su+U5YtTIkanrvcHRruAgq3PdOlHo/9nDxw66Kf1m+HggHTVCHuCJI/+gCYc0nLc1qpJL5v3hgEn+laVr3Us+AkkAEVPZdgZEtZYxSmj1LpSajsnFmH9goJOBQHHxEsff3Wdd528SLhGAILSYemKgA7nL0zOSPTCk3mEORlSdwmFITiNGUrJ1WueGAZsxfrnbwmAIYMnEiAj/+1MmcySk8upAFYyjhJ5cYYphNJohIbrWd/Bgwpr3Qp/Tb/l3sQVKqELmpej41YDVm/T+4bvz3BHXv9CIBrNJPYLIspqZJiQcBmKM= tippy@DESKTOP-PMU48VM" ];
    };
  };
}
