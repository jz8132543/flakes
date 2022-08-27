{ ... }:

let
  name = "root";
  homeDirectory = "/home/${name}";
in{
  users.users.root = {
    initialPassword = "$6$T8HN3fbLSFq/QvjD$jb4zGjl.V1EcYkQhP4GcIVRsLf8SJUs6Mx9NCO2jl43AtOZTBj4JQ0OJafA5/ZMRwakjW3FP5ImrYBh2z4k/V/" ;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq"
    ];
  };
}
