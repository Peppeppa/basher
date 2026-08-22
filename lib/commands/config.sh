#!/usr/bin/env bash
# lib/commands/config.sh - basher config ... , s. Architekturplan 2.4

cmd_config() {
    local action="${1:-}"

    case "$action" in
        get)
            shift
            [ $# -ge 1 ] || basher_die "Nutzung: basher config get <key>"
            basher_config_get "$1"
            ;;
        set)
            shift
            [ $# -ge 2 ] || basher_die "Nutzung: basher config set <key> <value>"
            local key="$1" value="$2"
            if ! printf '%s\n' "${BASHER_DEFAULT_KEYS[@]}" | grep -qx "$key"; then
                echo "basher: Hinweis - '$key' ist kein bekannter Config-Key, wird trotzdem gesetzt." >&2
            fi
            basher_config_set "$key" "$value"
            echo "basher: $key = '$value'"
            ;;
        path)
            echo "$BASHER_CONFIG_FILE"
            ;;
        edit)
            local editor
            editor="$(basher_resolve_editor)"
            "$editor" "$BASHER_CONFIG_FILE"
            ;;
        "")
            # Interaktiver Walkthrough nur im Voll-Modus (s. 2.3/2.4/Tabelle 6).
            # get/set/path/edit bleiben davon unberührt minimal-tauglich.
            require_full_install
            basher_config_walkthrough
            ;;
        *)
            basher_die "Unbekannte config-Aktion: '$action' (erwartet: get|set|path|edit, oder ohne Argument für Walkthrough)"
            ;;
    esac
}

basher_config_walkthrough() {
    echo "basher Config-Walkthrough - Enter übernimmt jeweils den aktuellen/Default-Wert."
    echo

    local key current input
    for key in "${BASHER_DEFAULT_KEYS[@]}"; do
        # INSTALL_MODE ist bewusst kein Teil des normalen Walkthroughs,
        # s. Architekturplan Abschnitt 8 (nur install.sh / Debug-'config set').
        [ "$key" = "INSTALL_MODE" ] && continue

        current="$(basher_config_get "$key")"
        [ -z "$current" ] && current="$(basher_config_default "$key")"

        while true; do
            read -r -p "$key [$current]: " input
            [ -z "$input" ] && input="$current"
            if basher_config_validate "$key" "$input"; then
                break
            fi
            echo "basher: $BASHER_CONFIG_VALIDATE_MSG - bitte erneut." >&2
        done

        basher_config_set "$key" "$input"
    done

    echo
    echo "basher: Config gespeichert unter $BASHER_CONFIG_FILE"
}
