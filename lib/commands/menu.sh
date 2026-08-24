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
        grep -v '^#' "$manifest" | grep -v '^$' | sort -t'|' -k1,1 |
        awk -F'|' '{ printf "%s\t%s\n", $1, $2 }' |
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
