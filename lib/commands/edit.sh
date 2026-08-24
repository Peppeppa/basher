#!/usr/bin/env bash
# lib/commands/edit.sh - basher edit [name-or-path], s. Architekturplan 5.3

cmd_edit() {
    local query="${1:-}"
    local relpath

    if [ -z "$query" ]; then
        require_full_install
        require_fzf
        relpath="$(basher_edit_pick_fzf)"
        [ -n "$relpath" ] || { echo "basher: Keine Auswahl getroffen."; return 0; }
    else
        relpath="$(basher_manifest_resolve "$REPO_PATH" "$query")"
        if [ -z "$relpath" ]; then
            basher_die "Kein Script für '$query' gefunden oder Auswahl abgebrochen (s. 'basher list')."
        fi
    fi

    local script_path="$REPO_PATH/$relpath"
    [ -f "$script_path" ] || basher_die "'$script_path' existiert nicht (Manifest evtl. veraltet - 'basher repo scan' ausführen)."

    # Gleiches Pre-Pull-Verhalten wie 'new' (s. 5.2/3.5), aus Konsistenzgründen.
    if [ "${AUTO_COMMIT:-false}" = "true" ] && [ "${SYNC_MODE:-auto}" = "auto" ]; then
        basher_repo_pull_rebase "$REPO_PATH" || true
    fi

    local editor
    editor="$(basher_resolve_editor)"
    "$editor" "$script_path"

    local current_desc new_desc
    current_desc="$(basher_manifest_get_description "$REPO_PATH" "$relpath")"
    read -r -p "Kurzbeschreibung [$current_desc]: " new_desc
    [ -z "$new_desc" ] && new_desc="$current_desc"
    basher_manifest_add "$REPO_PATH" "$script_path" "$new_desc"

    if [ "${AUTO_COMMIT:-false}" = "true" ]; then
        basher_repo_commit "$REPO_PATH" "basher: edit ${relpath}"
        [ "${SYNC_MODE:-auto}" = "auto" ] && { basher_repo_sync "$REPO_PATH" || true; }
    fi

    echo "basher: Bearbeitet: $script_path"
}

basher_edit_pick_fzf() {
    local manifest
    manifest="$(basher_manifest_path "$REPO_PATH")"
    [ -f "$manifest" ] || basher_die "Kein manifest.idx gefunden - 'basher repo scan' ausführen."

    grep -v '^#' "$manifest" | grep -v '^$' | cut -d'|' -f1 | \
        fzf --prompt="Script bearbeiten> " --preview="cat '$REPO_PATH/{}'"
}
