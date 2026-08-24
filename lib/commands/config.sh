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
    cat << 'BANNER'
___.                    .__                     
\_ |__  _____     ______|  |__    ____ _______  
 | __ \ \__  \   /  ___/|  |  \ _/ __ \\_  __ \ 
 | \_\ \ / __ \_ \___ \ |   Y  \\  ___/ |  | \/ 
 |___  /(____  //____  >|___|  / \___  >|__|    
     \/      \/      \/      \/      \/         
                                                
                     config
BANNER
    echo

    local key current input hint
    for key in "${BASHER_DEFAULT_KEYS[@]}"; do
        # INSTALL_MODE ist bewusst kein Teil des normalen Walkthroughs,
        # s. Architekturplan Abschnitt 8 (nur install.sh / Debug-'config set').
        # REPO_URL wird nicht direkt abgefragt, sondern automatisch gesetzt,
        # wenn bei REPO_PATH eine Git-URL statt eines Pfads eingegeben wird
        # (s. basher_repo_set_smart in lib/repo.sh).
        [ "$key" = "INSTALL_MODE" ] && continue
        [ "$key" = "REPO_URL" ] && continue

        current="$(basher_config_get "$key")"
        [ -z "$current" ] && current="$(basher_config_default "$key")"

        hint="$(basher_config_hint "$key")"
        [ -n "$hint" ] && echo "  $hint"

        if [ "$key" = "REPO_PATH" ]; then
            read -r -p "$key [$(basher_bold "$current")]: " input
            [ -z "$input" ] && input="$current"
            if basher_looks_like_git_url "$input"; then
                basher_repo_set_smart "$input"
            else
                basher_config_set REPO_PATH "$input"
            fi
            echo
            continue
        fi

        while true; do
            read -r -p "$key [$(basher_bold "$current")]: " input
            [ -z "$input" ] && input="$current"
            if basher_config_validate "$key" "$input"; then
                break
            fi
            echo "basher: $BASHER_CONFIG_VALIDATE_MSG - bitte erneut." >&2
        done

        basher_config_set "$key" "$input"
        echo
    done

    echo "basher: Config gespeichert unter $BASHER_CONFIG_FILE"
}
