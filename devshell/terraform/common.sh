#!@shell@
# shellcheck shell=bash

function message {
  green='\033[0;32m'
  no_color='\033[0m'
  echo -e "${green}>${no_color} $1" >&2
}
