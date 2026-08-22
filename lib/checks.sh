#!/usr/bin/env bash
# lib/checks.sh - Guard-Funktionen: aussagekräftige Fehler statt Crashes
#
# Siehe Architekturplan Abschnitt 1.5. Jeder Subcommand ruft die passenden
# Guards am Anfang seiner cmd_*()-Funktion auf, statt eigene Ad-hoc-Prüfungen
# zu bauen. Neue Befehle bekommen Fehlerbehandlung so "geschenkt".

basher_die() {
    echo "basher: $*" >&2
    exit 1
}

# Bricht ab, wenn keine Vollinstallation aktiv ist (s. 5.4: basher menu).
require_full_install() {
    if [ "${INSTALL_MODE:-}" != "full" ]; then
        basher_die "Diese Funktion ist nur in der Vollinstallation verfügbar (aktuell: '${INSTALL_MODE:-nicht gesetzt}').
Führe 'install.sh --full' aus, um zu wechseln."
    fi
}

# Bricht ab, wenn fzf trotz INSTALL_MODE=full nicht gefunden wird
# (z.B. manuell deinstalliert).
require_fzf() {
    if ! command -v fzf > /dev/null 2>&1; then
        basher_die "fzf wurde nicht gefunden, obwohl die Vollinstallation aktiv ist.
Installiere fzf über deinen Paketmanager oder führe 'install.sh --full' erneut aus."
    fi
}

# Prüft, ob im Root von <repo_path> ein manifest.idx liegt (s. 3.4/3.6).
# Gibt bei Erfolg den Pfad zur Manifest-Datei auf stdout aus.
require_manifest() {
    local repo_path="$1"
    local manifest="$repo_path/manifest.idx"

    if [ ! -f "$manifest" ]; then
        basher_die "Kein manifest.idx im Root von '$repo_path' gefunden.
Das scheint kein gültiger basher-Script-Store zu sein."
    fi

    printf '%s\n' "$manifest"
}

# Anders als die übrigen Guards hier bewusst KEIN basher_die: fehlendes gpg
# ist laut 4.3 kein harter Fehler, sondern löst einen stillen Fallback auf
# SECRETS_MODE=plain aus. Rückgabewert 1 signalisiert "nicht verfügbar",
# der Aufrufer entscheidet selbst, was er daraus macht.
require_gpg() {
    command -v gpg > /dev/null 2>&1
}
