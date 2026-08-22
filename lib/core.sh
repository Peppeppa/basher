#!/usr/bin/env bash
# lib/core.sh - gemeinsame Hilfsfunktionen, die von mehreren Befehlen genutzt werden.
# Setzt lib/checks.sh voraus (basher_die), s. Ladereihenfolge in bin/basher.

# Fallback-Kette aus 1.3: EDITOR_CMD (Config) -> $EDITOR (Env) -> nvim -> vim -> vi.
# Gibt den ersten tatsächlich vorhandenen Editor-Befehl auf stdout aus.
basher_resolve_editor() {
    local candidates=("${EDITOR_CMD:-}" "${EDITOR:-}" "nvim" "vim" "vi")
    local c
    for c in "${candidates[@]}"; do
        [ -z "$c" ] && continue
        if command -v "$c" > /dev/null 2>&1; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    basher_die "Kein Editor gefunden (weder EDITOR_CMD noch \$EDITOR noch nvim/vim/vi verfügbar)."
}
