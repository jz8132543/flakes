{ fetchurl }:
{
  # Fetch icons from reliable online sources with pinned hashes.
  # No local icon files are stored in git.
  wechat = fetchurl {
    url = "https://raw.githubusercontent.com/simple-icons/simple-icons/16.31.0/icons/wechat.svg";
    sha256 = "1jj39iklazfniq9w9z34ynb9kqbmz6sk6jb4rdwwwdsk64yqpd3l";
  };
  syncthing = fetchurl {
    url = "https://raw.githubusercontent.com/simple-icons/simple-icons/16.31.0/icons/syncthing.svg";
    sha256 = "1gfcg5203sj143hbng8ih84nmlk7g7z8w264rx4xhavsm9f13kd4";
  };
  doubao = fetchurl {
    url = "https://lf-flow-web-cdn.doubao.com/obj/flow-doubao/favicon/new-doubao/192x192.png";
    sha256 = "0f7cb9hqzipv3avm2rq87ijfzdir70scjhhsgwgc39p3jjyjmfys";
  };
  gemini = fetchurl {
    url = "https://raw.githubusercontent.com/simple-icons/simple-icons/16.31.0/icons/googlegemini.svg";
    sha256 = "1833k0z9ng13hk771f5pvcj86pkqb5sd37m387lh21048s48s8m6";
  };
  deepseek = fetchurl {
    url = "https://raw.githubusercontent.com/simple-icons/simple-icons/16.31.0/icons/deepseek.svg";
    sha256 = "1vz26i4v3yvl3sa14ih3yq4r53s771l7v01jgnx6w48x76ks0mbs";
  };
}
