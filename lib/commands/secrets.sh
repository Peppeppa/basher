#!/usr/bin/env bash
# lib/commands/secrets.sh - basher secrets ..., s. Architekturplan 4

cmd_secrets() {
    local action="${1:-}"
    [ $# -gt 0 ] && shift

    case "$action" in
        edit)
            basher_secrets_ensure
            basher_secrets_edit
            ;;
        set)
            [ $# -ge 2 ] || basher_die "Nutzung: basher secrets set <KEY> <WERT>"
            basher_secrets_ensure
            basher_secrets_set "$1" "$2"
            ;;
        get)
            [ $# -ge 1 ] || basher_die "Nutzung: basher secrets get <KEY>"
            basher_secrets_get "$1"
            ;;
        list|keys)
            basher_secrets_list_keys
            ;;
        encrypt)
            basher_secrets_encrypt
            ;;
        decrypt)
            basher_secrets_decrypt
            ;;
        "")
            basher_die "Nutzung: basher secrets <edit|set|get|list|encrypt|decrypt>"
            ;;
        *)
            basher_die "Unbekannte secrets-Aktion: '$action' (edit|set|get|list|encrypt|decrypt)"
            ;;
    esac
}
