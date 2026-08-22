#!/usr/bin/env bash
# lib/commands/repo.sh - basher repo scan|set|sync, s. 3.3/3.5 + scan (Ergänzung)

cmd_repo() {
    local action="${1:-}"
    [ $# -gt 0 ] && shift

    case "$action" in
        scan)
            basher_manifest_scan "${1:-$REPO_PATH}"
            ;;
        sync)
            basher_repo_sync "$REPO_PATH"
            ;;
        set)
            [ $# -ge 1 ] || basher_die "Nutzung: basher repo set <pfad>"
            basher_config_set REPO_PATH "$1"
            echo "basher: REPO_PATH gesetzt auf '$1'"
            ;;
        "")
            basher_die "Nutzung: basher repo <scan|set|sync> [Argumente]"
            ;;
        *)
            basher_die "Unbekannte repo-Aktion: '$action' (scan|set|sync)"
            ;;
    esac
}
