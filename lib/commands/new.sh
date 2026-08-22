#!/usr/bin/env bash
# lib/commands/new.sh - basher new [name] [--category <pfad>], s. 5.2

cmd_new() {
    local name="" category=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --category)
                shift
                [ "$#" -ge 1 ] || basher_die "Nutzung: --category <pfad>"
                category="$1"
                shift
                ;;
            --*)
                basher_die "Unbekannte Option: $1"
                ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                else
                    basher_die "Zu viele Argumente: '$1'"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$name" ]; then
        read -r -p "Name des neuen Scripts (ohne .sh): " name
        [ -n "$name" ] || basher_die "Kein Name angegeben, abgebrochen."
    fi
    name="${name%.sh}"

    mkdir -p "$REPO_PATH" || basher_die "Konnte REPO_PATH '$REPO_PATH' nicht anlegen."

    local target_dir="$REPO_PATH"
    [ -n "$category" ] && target_dir="$REPO_PATH/$category"
    mkdir -p "$target_dir" || basher_die "Konnte Kategorie-Pfad '$target_dir' nicht anlegen."

    local script_path="$target_dir/${name}.sh"
    [ -e "$script_path" ] && basher_die "'$script_path' existiert bereits."

    # Pre-Pull vor dem Editieren (s. 3.5) - löst "vergesse zu pullen, bevor
    # ich Änderungen mache" an der Wurzel statt erst nachträglich bei sync.
    if [ "${AUTO_COMMIT:-false}" = "true" ] && [ "${SYNC_MODE:-auto}" = "auto" ]; then
        basher_repo_pull_rebase "$REPO_PATH" || true
    fi

    printf '#!/usr/bin/env bash\n\n' > "$script_path"
    chmod +x "$script_path"

    local editor
    editor="$(basher_resolve_editor)"
    "$editor" "$script_path"

    local description
    read -r -p "Kurzbeschreibung (optional): " description
    basher_manifest_add "$REPO_PATH" "$script_path" "$description"

    if [ "${AUTO_COMMIT:-false}" = "true" ]; then
        basher_repo_commit "$REPO_PATH" "basher: add ${name}.sh"
        [ "${SYNC_MODE:-auto}" = "auto" ] && { basher_repo_sync "$REPO_PATH" || true; }
    fi

    echo "basher: Script erstellt: $script_path"
}
