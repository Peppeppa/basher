#!/usr/bin/env bash
# lib/commands/tmp.sh - basher tmp, s. Architekturplan 5.1
#
# Ablauf: Datei anlegen (Shebang, +x) -> Editor öffnen -> leer? verwerfen ->
# Syntax-Check (Warnung, kein Blocker) -> "Ausführen? [j/N]" -> N: löschen,
# fertig / J: ausführen -> "Nochmal ausführen? [j/N]" -> N: löschen, fertig /
# J: zurück zur Ausführung. Landet nie im Script-Repo bzw. Manifest (s. 3.1).

cmd_tmp() {
    local ts tmpfile
    mkdir -p "$TMP_DIR" || basher_die "Konnte TMP_DIR '$TMP_DIR' nicht anlegen."

    ts="$(date +%Y%m%d-%H%M%S)"
    tmpfile="$TMP_DIR/bashertmp-${ts}-$$.sh"

    printf '#!/usr/bin/env bash\n\n' > "$tmpfile"
    chmod +x "$tmpfile"

    local editor
    editor="$(basher_resolve_editor)"
    "$editor" "$tmpfile"

    if ! basher_tmp_has_content "$tmpfile"; then
        echo "basher: Script ist leer, wird verworfen."
        rm -f "$tmpfile"
        return 0
    fi

    basher_tmp_syntax_check "$tmpfile"
    basher_tmp_run_loop "$tmpfile"

    rm -f "$tmpfile"
    echo "basher: Tmp-Script gelöscht ($tmpfile)."
}

# Prüft, ob außer Shebang/Leerzeilen tatsächlich Inhalt im Script steht.
basher_tmp_has_content() {
    local file="$1"
    grep -vE '^#!|^[[:space:]]*$' "$file" | grep -q .
}

# Nur Warnung, kein Blocker (s. 1.3: "Rückfrage ob ausgeführt werden soll",
# der Syntax-Check informiert dabei nur mit).
basher_tmp_syntax_check() {
    local file="$1"
    [ "${AUTO_SYNTAX_CHECK:-true}" = "true" ] || return 0

    local err
    err="$(bash -n "$file" 2>&1)" || {
        echo "basher: Warnung - Syntax-Fehler im Script:" >&2
        echo "$err" >&2
    }
}

basher_tmp_run_loop() {
    local file="$1" answer

    read -r -p "Ausführen? [j/N]: " answer
    case "$answer" in
        j|J)
            while true; do
                basher_secrets_load
                bash "$file"
                echo "basher: Script beendet (exit $?)."
                read -r -p "Nochmal ausführen? [j/N]: " answer
                case "$answer" in
                    j|J) continue ;;
                    *) break ;;
                esac
            done
            ;;
        *) : ;;
    esac
}
