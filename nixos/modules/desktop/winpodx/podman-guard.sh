# shellcheck shell=bash
set -euo pipefail
real=${WINPODX_REAL_PODMAN:-@podman@}
dir=${XDG_CONFIG_HOME:-$HOME/.config}/winpodx
command=${1:-}
entity=container
[[ $command != pod ]] || entity=pod
if [[ $command == container || $command == pod || $command == volume || $command == system ]]; then
  command=${2:-}
fi
case "$command" in
check | pause | stop | restart | kill | rm | remove | prune | run | create)
  mkdir -p "$dir"
  exec 8>"$dir/deployment.guard.lock"
  flock 8
  if [[ -e $dir/deployment.pending ]]; then
    case "$command" in
    run | create)
      # First creation is allowed; replacement of an installed pod is not.
      name=""
      next=false
      replace=false
      for arg in "$@"; do
        if $next; then
          name=$arg
          next=false
        fi
        case "$arg" in
        --name) next=true ;;
        --name=*) name=${arg#--name=} ;;
        --replace | --replace=true) replace=true ;;
        esac
      done
      if ! $replace || { [[ -n $name ]] && ! "$real" "$entity" exists "$name"; }; then
        "$real" "$@"
        exit $?
      fi
      ;;
    esac
    printf '%s\n' 'WinPodX deployment is unfinished; pause/stop/replacement is temporarily disabled.' >&2
    exit 75
  fi
  [[ $command != check ]] || exit 0
  # Retain the lock in this parent through the runtime operation.
  "$real" "$@"
  ;;
*) exec "$real" "$@" ;;
esac
