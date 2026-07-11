#!/bin/zsh
set -euo pipefail

usage() {
  print "Server Observer CLI"
  print "  server-observer refresh"
  print "  server-observer open"
  print "  server-observer start|stop|restart <project name or path>"
}

action="${1:-open}"
case "$action" in
  open|refresh)
    /usr/bin/open -g "serverobserver://$action"
    ;;
  start|stop|restart)
    project="${2:-}"
    if [[ -z "$project" ]]; then usage; exit 2; fi
    encoded="${project//\%/%25}"
    encoded="${encoded// /%20}"
    encoded="${encoded//\#/%23}"
    encoded="${encoded//\&/%26}"
    encoded="${encoded//\?/%3F}"
    /usr/bin/open -g "serverobserver://$action?project=$encoded"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
