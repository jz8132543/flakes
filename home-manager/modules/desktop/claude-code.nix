{ pkgs, ... }:
{
  home.packages = [ pkgs.claude-code ];

  home.global-persistence = {
    directories = [
      ".claude"
      ".config/claude"
    ];
    files = [ ".claude.json" ];
  };
}
