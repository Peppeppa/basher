#!/usr/bin/env bash
# lib/commands/menu.sh - basher menu, s. Architekturplan 5.4
# Interaktives fzf-Menü mit Preview-Pane. Enter fuehrt direkt aus (ruft
# cmd_run), Ctrl-E oeffnet zum Bearbeiten (ruft cmd_edit) - beides nutzt
# denselben Code wie die eigenstaendigen Befehle, kein Duplikat.

cmd_menu() {
    require_full_install
    require_fzf

    local manifest="$REPO_PATH/manifest.idx"
    [ -f "$manifest" ] || basher_die "Kein manifest.idx in '$REPO_PATH' gefunden - 'basher repo scan' ausführen."

    local preview_cmd
    if command -v bat > /dev/null 2>&1; then
        preview_cmd="bat --style=plain --color=always '$REPO_PATH'/{1} 2>/dev/null"
    else
        preview_cmd="cat '$REPO_PATH'/{1} 2>/dev/null"
    fi

    local selection action key
    selection="$(
        while IFS='|' read -r manifest_key description; do
            [ -z "$manifest_key" ] && continue
            [[ "$manifest_key" == \#* ]] && continue

            # Normalerweise enthält das Manifest bereits relative Pfade. Für
            # ältere/manuell gepflegte Manifeste schneiden wir REPO_PATH hier
            # ebenfalls ab, damit fzf nie den kompletten absoluten Pfad zeigt.
            key="$(basher_manifest_relpath "$REPO_PATH" "$manifest_key")"

            printf '%s\t%s\n' "$key" "$description"
        done < "$manifest" |
        sort -t$'\t' -k1,1 |
        fzf --delimiter='\t' --with-nth=1,2 \
            --prompt="basher> " \
            --header="Enter=ausführen  Ctrl-E=bearbeiten  Esc=abbrechen" \
            --preview="$preview_cmd" \
            --expect=ctrl-e
    )"

    action="$(printf '%s\n' "$selection" | sed -n '1p')"
    key="$(printf '%s\n' "$selection" | sed -n '2p' | cut -f1)"

    [ -n "$key" ] || { echo "basher: Keine Auswahl getroffen."; return 0; }

    if [ "$action" = "ctrl-e" ]; then
        cmd_edit "$key"
    else
        cmd_run "$key"
    fi
}
