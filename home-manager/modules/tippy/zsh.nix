{ ... }:
{
  programs.starship = {
    enable = true;
  };

  programs.zsh = {
    enable = true;
    history.path = "$HOME/.cache/zsh_history";

    enableVteIntegration = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    enableCompletion = true;
  };
}
