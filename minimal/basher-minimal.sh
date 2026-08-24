#!/usr/bin/env bash
# basher-minimal.sh - AUTOMATISCH GENERIERT aus lib/*.sh, s. build-minimal.sh
# NICHT VON HAND BEARBEITEN - Änderungen gehen bei der nächsten Generierung
# verloren. Quelle der Wahrheit: lib/*.sh in diesem Repo.
#
# Generiert am 2026-08-24T10:01:38Z

set -uo pipefail
trap 'exit 1' TERM  # s. Kommentar zu basher_die in lib/checks.sh

# ===== lib/config.sh =====
# lib/config.sh - Config laden, Defaults setzen, lesen/schreiben
#
# Siehe Architekturplan Abschnitt 2. Format: einfache KEY="value"-Datei,
# direkt in Bash sourcebar (kein YAML/JSON-Parser -> Minimal-Modus-tauglich).

BASHER_CONFIG_DIR="${BASHER_CONFIG_DIR:-$HOME/.config/basher}"
BASHER_CONFIG_FILE="${BASHER_CONFIG_FILE:-$BASHER_CONFIG_DIR/config}"

# Reihenfolge entspricht der Tabelle in 2.2.
# INSTALL_MODE bewusst ohne sinnvollen Default - wird von install.sh gesetzt
# (s. Abschnitt 8: technisch per 'basher config set' überschreibbar, aber
# kein beworbener Workflow, nur Debug-Hintertür).
BASHER_DEFAULT_KEYS=(
    INSTALL_MODE
    REPO_PATH
    REPO_URL
    EDITOR_CMD
    TMP_DIR
    AUTO_SYNTAX_CHECK
    AUTO_COMMIT
    SYNC_MODE
    SECRETS_MODE
    SECRETS_FILE
)

basher_config_default() {
    case "$1" in
        INSTALL_MODE)      echo "" ;;
        REPO_PATH)         echo "$HOME/.local/share/basher/scripts" ;;
        REPO_URL)          echo "" ;;
        EDITOR_CMD)        echo "" ;;
        TMP_DIR)           echo "${TMPDIR:-/tmp}/basher" ;;
        AUTO_SYNTAX_CHECK) echo "true" ;;
        AUTO_COMMIT)       echo "false" ;;
        SYNC_MODE)         echo "auto" ;;
        SECRETS_MODE)      echo "plain" ;;
        SECRETS_FILE)      echo "$BASHER_CONFIG_DIR/secrets.env" ;;
        *)                 echo "" ;;
    esac
}

basher_config_write_defaults() {
    mkdir -p "$BASHER_CONFIG_DIR"
    {
        echo "# basher config - siehe docs/architecture.md Abschnitt 2.2"
        local key
        for key in "${BASHER_DEFAULT_KEYS[@]}"; do
            printf '%s="%s"\n' "$key" "$(basher_config_default "$key")"
        done
    } > "$BASHER_CONFIG_FILE"
}

# Validiert Werte für Keys mit festem Wertebereich (Enum/Bool). Freitext-Keys
# (Pfade, URLs, ...) werden nicht eingeschränkt. Bei Ungültigkeit landet die
# Begründung in BASHER_CONFIG_VALIDATE_MSG, Rückgabewert 1.
basher_config_validate() {
    local key="$1" value="$2"
    case "$key" in
        AUTO_SYNTAX_CHECK|AUTO_COMMIT)
            [[ "$value" == "true" || "$value" == "false" ]] && return 0
            BASHER_CONFIG_VALIDATE_MSG="$key erwartet 'true' oder 'false', bekommen: '$value'"
            return 1
            ;;
        SYNC_MODE)
            [[ "$value" == "auto" || "$value" == "pro" ]] && return 0
            BASHER_CONFIG_VALIDATE_MSG="SYNC_MODE erwartet 'auto' oder 'pro', bekommen: '$value'"
            return 1
            ;;
        SECRETS_MODE)
            [[ "$value" == "plain" || "$value" == "gpg" ]] && return 0
            BASHER_CONFIG_VALIDATE_MSG="SECRETS_MODE erwartet 'plain' oder 'gpg', bekommen: '$value'"
            return 1
            ;;
        INSTALL_MODE)
            [[ -z "$value" || "$value" == "minimal" || "$value" == "full" ]] && return 0
            BASHER_CONFIG_VALIDATE_MSG="INSTALL_MODE erwartet 'minimal' oder 'full', bekommen: '$value'"
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Lädt die Config-Datei. Existiert sie nicht, wird sie mit Defaults angelegt
# (Minimal-Modus: still, kein Prompt möglich - s. 2.3). Fehlt ein einzelner
# Key (z.B. nach einem Update, das einen neuen Key einführt), wird nur der
# fehlende Key ergänzt - additiv, kein Config-Versionsfeld nötig (s. 2.3).
basher_config_load() {
    mkdir -p "$BASHER_CONFIG_DIR"

    if [ ! -f "$BASHER_CONFIG_FILE" ]; then
        basher_config_write_defaults
    fi

    local key missing=0
    for key in "${BASHER_DEFAULT_KEYS[@]}"; do
        if ! grep -q "^${key}=" "$BASHER_CONFIG_FILE" 2>/dev/null; then
            printf '%s="%s"\n' "$key" "$(basher_config_default "$key")" >> "$BASHER_CONFIG_FILE"
            missing=1
        fi
    done

    # shellcheck source=/dev/null
    source "$BASHER_CONFIG_FILE"

    if [ "$missing" -eq 1 ]; then
        echo "basher: Config um neue(n) Key(s) ergänzt (${BASHER_CONFIG_FILE})" >&2
    fi
}

basher_config_get() {
    local key="$1"
    printf '%s\n' "${!key:-}"
}

# Schreibt einen Key persistent in die Config-Datei UND setzt ihn in der
# laufenden Shell-Session (declare -g), damit nachfolgender Code im selben
# Aufruf sofort den neuen Wert sieht.
basher_config_set() {
    local key="$1" value="$2"

    if ! basher_config_validate "$key" "$value"; then
        basher_die "$BASHER_CONFIG_VALIDATE_MSG"
    fi

    if [ ! -f "$BASHER_CONFIG_FILE" ]; then
        basher_config_write_defaults
    fi

    if grep -q "^${key}=" "$BASHER_CONFIG_FILE"; then
        local tmp
        tmp="$(mktemp)"
        awk -v k="$key" -v v="$value" '
            BEGIN { FS="="; OFS="=" }
            $1 == k { print k"=\""v"\""; next }
            { print }
        ' "$BASHER_CONFIG_FILE" > "$tmp" && mv "$tmp" "$BASHER_CONFIG_FILE"
    else
        printf '%s="%s"\n' "$key" "$value" >> "$BASHER_CONFIG_FILE"
    fi

    declare -g "$key=$value"
}

# ===== lib/checks.sh =====
# lib/checks.sh - Guard-Funktionen: aussagekräftige Fehler statt Crashes
#
# Siehe Architekturplan Abschnitt 1.5. Jeder Subcommand ruft die passenden
# Guards am Anfang seiner cmd_*()-Funktion auf, statt eigene Ad-hoc-Prüfungen
# zu bauen. Neue Befehle bekommen Fehlerbehandlung so "geschenkt".

basher_die() {
    echo "basher: $*" >&2
    # exit allein reicht nicht: wird basher_die aus einer Funktion heraus
    # aufgerufen, die per $(...) eingebunden ist (z.B. editor="$(basher_resolve_editor)"),
    # würde ein simples 'exit' nur die Subshell der Command-Substitution
    # beenden - das Hauptskript liefe mit einem leeren Rückgabewert einfach
    # weiter, statt abzubrechen. $$ referenziert laut Bash-Doku auch innerhalb
    # von Subshells immer die PID des äußersten Skripts, daher beendet
    # 'kill -s TERM "$$"' + der TERM-Trap (s. bin/basher) zuverlässig das
    # gesamte Skript, unabhängig davon, aus welcher Verschachtelungstiefe
    # basher_die aufgerufen wird.
    kill -s TERM "$$" 2>/dev/null
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

# ===== lib/core.sh =====
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

# ===== lib/repo.sh =====
# lib/repo.sh - Git-Interaktion für REPO_PATH, s. Architekturplan 3.5

basher_repo_is_git() {
    local repo_path="$1"
    [ -d "$repo_path/.git" ]
}

# Nur der Pull-Teil, für den Pre-Pull vor new/edit (s. 5.2/5.3). Bricht bei
# echtem Rebase-Konflikt sauber ab (kein halb-gerebaster Zustand) und gibt
# eine klare Meldung statt eines rohen Git-Fehlers.
basher_repo_pull_rebase() {
    local repo_path="$1"

    # Kein Upstream-Tracking-Branch konfiguriert (frisches Repo, Remote
    # gerade erst hinzugefügt, o.ä.) -> nichts zu pullen, kein Fehler.
    # Ohne diesen Check würde 'git pull --rebase' hier mit "no tracking
    # information" fehlschlagen, was fälschlich wie ein Konflikt aussieht.
    if ! git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' > /dev/null 2>&1; then
        return 0
    fi

    git -C "$repo_path" fetch --quiet || {
        echo "basher: Warnung - 'git fetch' fehlgeschlagen (kein Netzwerk/kein Remote?), Pull übersprungen." >&2
        return 1
    }

    if ! git -C "$repo_path" pull --rebase --quiet; then
        git -C "$repo_path" rebase --abort 2>/dev/null
        basher_die "Konflikt beim Sync in '$repo_path' - bitte manuell prüfen (git status), oder SYNC_MODE=pro setzen, um Automatik zu deaktivieren."
    fi
}

# Committet alle Änderungen in REPO_PATH, falls AUTO_COMMIT genutzt wird.
# Kein Fehler, falls kein Git-Repo oder nichts zu committen ist.
basher_repo_commit() {
    local repo_path="$1" message="$2"

    if ! basher_repo_is_git "$repo_path"; then
        echo "basher: Hinweis - AUTO_COMMIT ist aktiv, aber '$repo_path' ist kein Git-Repo. Committe nicht." >&2
        return 0
    fi

    git -C "$repo_path" add -A
    if git -C "$repo_path" diff --cached --quiet; then
        return 0
    fi
    git -C "$repo_path" commit --quiet -m "$message"
}

# Öffentlicher Einstiegspunkt, u.a. für 'basher repo sync' (später) und den
# automatischen Sync nach new/edit bei AUTO_COMMIT+SYNC_MODE=auto.
basher_repo_sync() {
    local repo_path="$1"

    if ! basher_repo_is_git "$repo_path"; then
        echo "basher: '$repo_path' ist kein Git-Repo, überspringe Sync." >&2
        return 0
    fi

    if [ "${SYNC_MODE:-auto}" = "pro" ]; then
        basher_repo_status_only "$repo_path"
        return $?
    fi

    basher_repo_pull_rebase "$repo_path" || return 1

    if ! git -C "$repo_path" push --quiet; then
        echo "basher: Warnung - 'git push' fehlgeschlagen (kein Netzwerk/kein Remote konfiguriert?)." >&2
        return 1
    fi

    echo "basher: Repo synchronisiert (pull --rebase + push)."
}

# SYNC_MODE=pro: nichts automatisch verändern, nur Status anzeigen (s. 3.5).
basher_repo_status_only() {
    local repo_path="$1"

    if ! git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' > /dev/null 2>&1; then
        echo "basher: Kein Upstream-Branch konfiguriert - nichts zu vergleichen."
        return 0
    fi

    git -C "$repo_path" fetch --quiet || {
        echo "basher: Warnung - 'git fetch' fehlgeschlagen (kein Netzwerk?)." >&2
        return 1
    }

    local ahead behind
    ahead="$(git -C "$repo_path" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    behind="$(git -C "$repo_path" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"

    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        echo "basher: Repo ist mit Remote synchron."
    else
        echo "basher: $behind Commit(s) hinter Remote, $ahead eigene(r) Commit(s) voraus - bitte manuell pullen/pushen (SYNC_MODE=pro)."
    fi
}

# ===== lib/manifest.sh =====
# lib/manifest.sh - manifest.idx lesen/schreiben, s. Architekturplan 3.6

BASHER_MANIFEST_HEADER="# basher-manifest v1"

basher_manifest_path() {
    printf '%s\n' "$1/manifest.idx"
}

basher_manifest_ensure() {
    local repo_path="$1" manifest
    manifest="$(basher_manifest_path "$repo_path")"
    [ -f "$manifest" ] || echo "$BASHER_MANIFEST_HEADER" > "$manifest"
}

# Fügt einen Eintrag hinzu bzw. aktualisiert die Beschreibung eines
# bestehenden Eintrags mit demselben relativen Pfad (z.B. bei 'edit').
basher_manifest_add() {
    local repo_path="$1" script_path="$2" description="${3:-}"
    local manifest relpath tmp

    basher_manifest_ensure "$repo_path"
    manifest="$(basher_manifest_path "$repo_path")"
    relpath="${script_path#"$repo_path"/}"

    tmp="$(mktemp)"
    awk -v rp="$relpath" -v desc="$description" -F'|' '
        BEGIN { OFS="|"; found=0 }
        /^#/ { print; next }
        NF==0 { next }
        $1 == rp { print rp, desc; found=1; next }
        { print }
        END { if (!found) print rp, desc }
    ' "$manifest" > "$tmp" && mv "$tmp" "$manifest"
}

basher_manifest_get_description() {
    local repo_path="$1" relpath="$2" manifest
    manifest="$(basher_manifest_path "$repo_path")"
    [ -f "$manifest" ] || { echo ""; return 0; }
    awk -F'|' -v rp="$relpath" '$1==rp {print $2; found=1} END{if(!found) print ""}' "$manifest"
}

# Löst eine Nutzereingabe (Name oder Pfad, mit/ohne .sh) zu genau einem
# Manifest-Eintrag auf. Gibt bei eindeutigem Treffer den relativen Pfad auf
# stdout aus. Rückgabewert 1 bei "nicht gefunden" ODER "mehrdeutig" - im
# mehrdeutigen Fall werden die Kandidaten zusätzlich auf stderr gelistet,
# der Aufrufer entscheidet über die konkrete Fehlermeldung (s. 1.5).
basher_manifest_resolve() {
    local repo_path="$1" query="$2"
    local manifest
    manifest="$(basher_manifest_path "$repo_path")"
    [ -f "$manifest" ] || return 1

    query="${query%.sh}"

    local key desc key_noext
    local -a exact=() partial=()
    while IFS='|' read -r key desc; do
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue
        key_noext="${key%.sh}"
        if [ "$key_noext" = "$query" ]; then
            exact+=("$key")
        elif [ "$(basename "$key_noext")" = "$query" ]; then
            partial+=("$key")
        fi
    done < "$manifest"

    local -a candidates=()
    if [ "${#exact[@]}" -gt 0 ]; then
        candidates=("${exact[@]}")
    else
        candidates=("${partial[@]}")
    fi

    case "${#candidates[@]}" in
        0) return 1 ;;
        1) printf '%s\n' "${candidates[0]}"; return 0 ;;
        *) basher_manifest_disambiguate "$repo_path" "${candidates[@]}" ;;
    esac
}

# Mehrere Treffer für denselben Namen (s. Backlog 9.1, z.B. zwei
# dracut-install.sh in unterschiedlichen Kategorien): statt abzubrechen wird
# eine Auswahl angeboten. Im Voll-Modus per fzf (mit Preview), sonst - und
# damit auch im Minimal-/curl-Fall - eine simple nummerierte Liste per read.
# Gibt bei Auswahl den gewählten relativen Pfad auf stdout aus, sonst 1
# (Abbruch/ungültige Eingabe - vom Aufrufer wie "nicht gefunden" behandelt).
basher_manifest_disambiguate() {
    local repo_path="$1"
    shift
    local -a candidates=("$@")

    if [ "${INSTALL_MODE:-}" = "full" ] && command -v fzf > /dev/null 2>&1; then
        local preview_cmd="cat '$repo_path'/{} 2>/dev/null"
        printf '%s\n' "${candidates[@]}" |
            fzf --prompt="Mehrdeutig, bitte wählen> " --preview="$preview_cmd"
        return $?
    fi

    echo "basher: Mehrere Treffer - bitte auswählen:" >&2
    local i=1 c
    for c in "${candidates[@]}"; do
        echo "  $i) $c" >&2
        i=$((i + 1))
    done

    local choice
    read -r -p "Auswahl [1-${#candidates[@]}]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#candidates[@]}" ]; then
        printf '%s\n' "${candidates[$((choice - 1))]}"
        return 0
    fi

    return 1
}

# Durchsucht repo_path rekursiv nach *.sh-Dateien und gleicht das Manifest ab:
# - neue Scripts werden mit leerer Beschreibung ergänzt
# - Einträge zu nicht mehr existierenden Dateien werden entfernt
# - bestehende Beschreibungen bleiben unangetastet
# Nützlich, um ein bereits per Ordnerstruktur kategorisiertes Repo (das noch
# kein manifest.idx hat) basher-tauglich zu machen.
basher_manifest_scan() {
    local repo_path="$1"
    [ -d "$repo_path" ] || basher_die "'$repo_path' existiert nicht."

    basher_manifest_ensure "$repo_path"
    local manifest
    manifest="$(basher_manifest_path "$repo_path")"

    local found_file rel
    local -A on_disk=()
    while IFS= read -r -d '' found_file; do
        rel="${found_file#"$repo_path"/}"
        on_disk["$rel"]=1
    done < <(find "$repo_path" -type f -name '*.sh' -not -path '*/.*' -print0)

    local key desc
    local -A existing_desc=()
    while IFS='|' read -r key desc; do
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue
        existing_desc["$key"]="$desc"
    done < "$manifest"

    local added=0 removed=0 kept=0
    local tmp
    tmp="$(mktemp)"

    for rel in "${!on_disk[@]}"; do
        if [ -n "${existing_desc[$rel]+x}" ]; then
            printf '%s|%s\n' "$rel" "${existing_desc[$rel]}" >> "$tmp"
            kept=$((kept + 1))
        else
            printf '%s|%s\n' "$rel" "" >> "$tmp"
            added=$((added + 1))
        fi
    done

    for rel in "${!existing_desc[@]}"; do
        [ -z "${on_disk[$rel]+x}" ] && removed=$((removed + 1))
    done

    sort -t'|' -k1,1 "$tmp" -o "$tmp" 2>/dev/null || true
    { echo "$BASHER_MANIFEST_HEADER"; cat "$tmp"; } > "$manifest"
    rm -f "$tmp"

    echo "basher: Manifest aktualisiert ($manifest) - $added neu, $removed entfernt, $kept unverändert."
}

# ===== lib/remote.sh =====
# lib/remote.sh - Ad-hoc-Zugriff auf ein beliebiges öffentliches GitHub-Repo
# über raw.githubusercontent.com, s. Architekturplan 3.4. Kein API-Call, kein
# Rate-Limit-Risiko - dafür müssen wir den Default-Branch selbst erraten.

BASHER_REMOTE_BRANCHES=(main master)

basher_remote_raw_url() {
    local repo_ref="$1" path="$2" branch="$3"
    printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$repo_ref" "$branch" "$path"
}

# Versucht <path> aus <repo_ref> zu laden, probiert main/master durch.
# Gibt bei Erfolg den tatsächlich funktionierenden Branch-Namen auf stdout aus.
basher_remote_fetch() {
    local repo_ref="$1" path="$2" dest="$3"
    local branch url

    for branch in "${BASHER_REMOTE_BRANCHES[@]}"; do
        url="$(basher_remote_raw_url "$repo_ref" "$path" "$branch")"
        if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
            printf '%s\n' "$branch"
            return 0
        fi
    done
    return 1
}

# Wie basher_remote_fetch, aber mit bereits bekanntem Branch (kein
# main/master-Ausprobieren nötig, z.B. wenn das Manifest den Branch schon
# bestätigt hat).
basher_remote_fetch_branch() {
    local repo_ref="$1" path="$2" dest="$3" branch="$4"
    local url
    url="$(basher_remote_raw_url "$repo_ref" "$path" "$branch")"
    curl -fsSL "$url" -o "$dest" 2>/dev/null
}

# ===== lib/secrets.sh =====
# lib/secrets.sh - Secrets laden/bearbeiten/migrieren, s. Architekturplan 4

# Pfad zur tatsächlichen Secrets-Datei je nach Modus. Im gpg-Modus hängt
# ".gpg" an SECRETS_FILE, im plain-Modus wird SECRETS_FILE direkt genutzt.
basher_secrets_path() {
    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        printf '%s\n' "${SECRETS_FILE}.gpg"
    else
        printf '%s\n' "$SECRETS_FILE"
    fi
}

basher_secrets_ensure() {
    local path
    path="$(basher_secrets_path)"
    mkdir -p "$(dirname "$path")"
    [ -f "$path" ] && return 0

    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        command -v gpg > /dev/null 2>&1 || basher_die "gpg nicht gefunden, kann keine verschlüsselte Secrets-Datei anlegen."
        : | gpg -c --output "$path" || basher_die "Konnte verschlüsselte Secrets-Datei nicht anlegen."
        chmod 600 "$path"
    else
        : > "$path"
        chmod 600 "$path"
    fi
}

# Prüft Dateirechte der Plain-Secrets-Datei, korrigiert bei Abweichung von
# 600 (s. 4.1). Für die verschlüsselte Variante nicht relevant.
basher_secrets_check_perms() {
    [ "${SECRETS_MODE:-plain}" = "gpg" ] && return 0
    local path="$SECRETS_FILE"
    [ -f "$path" ] || return 0

    local perms
    perms="$(stat -c '%a' "$path" 2>/dev/null)"
    if [ -n "$perms" ] && [ "$perms" != "600" ]; then
        echo "basher: Warnung - '$path' hatte Rechte $perms statt 600, korrigiert." >&2
        chmod 600 "$path"
    fi
}

basher_secrets_shred() {
    shred -u "$1" 2>/dev/null || rm -f "$1"
}

# Lädt Secrets in die aktuelle Shell-Umgebung (für auszuführende Scripts,
# s. cmd_run/cmd_tmp). Kein Fehler, falls keine Secrets-Datei existiert.
basher_secrets_load() {
    local path
    path="$(basher_secrets_path)"
    [ -f "$path" ] || return 0

    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        if ! command -v gpg > /dev/null 2>&1; then
            echo "basher: Warnung - SECRETS_MODE=gpg, aber gpg fehlt. Secrets werden NICHT geladen." >&2
            return 1
        fi
        set -a
        # shellcheck disable=SC1090
        source <(gpg -d --quiet "$path" 2>/dev/null)
        set +a
    else
        basher_secrets_check_perms
        set -a
        # shellcheck disable=SC1090
        source "$path"
        set +a
    fi
}

basher_secrets_edit() {
    local path
    path="$(basher_secrets_path)"
    local editor
    editor="$(basher_resolve_editor)"

    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        command -v gpg > /dev/null 2>&1 || basher_die "gpg nicht gefunden."
        local plain_tmp
        if [ -d /dev/shm ]; then
            plain_tmp="$(mktemp /dev/shm/basher-secrets.XXXXXX)"
        else
            echo "basher: Warnung - /dev/shm nicht verfügbar, temporärer Klartext landet kurzzeitig auf Platte." >&2
            plain_tmp="$(mktemp)"
        fi

        gpg -d --quiet --output "$plain_tmp" "$path" 2>/dev/null

        "$editor" "$plain_tmp"

        if gpg --yes -c --output "$path" "$plain_tmp"; then
            chmod 600 "$path"
            echo "basher: Secrets verschlüsselt gespeichert ($path)."
        else
            basher_secrets_shred "$plain_tmp"
            basher_die "Verschlüsselung fehlgeschlagen - Änderungen NICHT gespeichert."
        fi
        basher_secrets_shred "$plain_tmp"
    else
        basher_secrets_check_perms
        "$editor" "$path"
        chmod 600 "$path"
    fi
}

basher_secrets_set_in_file() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" -F'=' '
        BEGIN { OFS="="; found=0 }
        $1 == k { print k, "\"" v "\""; found=1; next }
        { print }
        END { if (!found) print k "=\"" v "\"" }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

basher_secrets_set() {
    local key="$1" value="$2" path
    path="$(basher_secrets_path)"

    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        command -v gpg > /dev/null 2>&1 || basher_die "gpg nicht gefunden."
        local tmp
        tmp="$(mktemp)"
        gpg -d --quiet --output "$tmp" "$path" 2>/dev/null
        basher_secrets_set_in_file "$tmp" "$key" "$value"
        if ! gpg --yes -c --output "$path" "$tmp"; then
            basher_secrets_shred "$tmp"
            basher_die "Verschlüsselung fehlgeschlagen."
        fi
        chmod 600 "$path"
        basher_secrets_shred "$tmp"
    else
        basher_secrets_set_in_file "$path" "$key" "$value"
        chmod 600 "$path"
    fi
    echo "basher: Secret '$key' gesetzt."
}

basher_secrets_get() {
    local key="$1" path value
    path="$(basher_secrets_path)"
    [ -f "$path" ] || basher_die "Keine Secrets-Datei vorhanden."
    basher_secrets_check_perms

    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        value="$(gpg -d --quiet "$path" 2>/dev/null | awk -F'=' -v k="$key" '$1==k{sub(/^[^=]*=/,""); gsub(/^"|"$/,""); print; exit}')"
    else
        value="$(awk -F'=' -v k="$key" '$1==k{sub(/^[^=]*=/,""); gsub(/^"|"$/,""); print; exit}' "$path")"
    fi

    [ -n "$value" ] || basher_die "Kein Secret mit Key '$key' gefunden."
    printf '%s\n' "$value"
}

basher_secrets_list_keys() {
    local path
    path="$(basher_secrets_path)"
    [ -f "$path" ] || { echo "basher: Keine Secrets-Datei vorhanden."; return 0; }
    basher_secrets_check_perms

    if [ "${SECRETS_MODE:-plain}" = "gpg" ]; then
        gpg -d --quiet "$path" 2>/dev/null | awk -F'=' 'NF{print $1}'
    else
        awk -F'=' 'NF{print $1}' "$path"
    fi
}

# Migriert plain -> gpg (einmalige Verschlüsselung, s. 4.2). Aktualisiert
# SECRETS_MODE erst NACH erfolgreicher Migration.
basher_secrets_encrypt() {
    command -v gpg > /dev/null 2>&1 || basher_die "gpg nicht gefunden - kann nicht auf SECRETS_MODE=gpg umstellen."
    [ "${SECRETS_MODE:-plain}" = "gpg" ] && basher_die "SECRETS_MODE ist bereits 'gpg'."

    local plain_path="$SECRETS_FILE" gpg_path="${SECRETS_FILE}.gpg"
    [ -f "$gpg_path" ] && basher_die "'$gpg_path' existiert bereits - keine automatische Überschreibung."

    if [ -f "$plain_path" ]; then
        gpg -c --output "$gpg_path" "$plain_path" || basher_die "Verschlüsselung fehlgeschlagen."
        chmod 600 "$gpg_path"
        basher_secrets_shred "$plain_path"
        echo "basher: '$plain_path' verschlüsselt nach '$gpg_path' (Klartext entfernt)."
    else
        : | gpg -c --output "$gpg_path" || basher_die "Konnte leere verschlüsselte Datei nicht anlegen."
        chmod 600 "$gpg_path"
        echo "basher: Leere verschlüsselte Secrets-Datei angelegt ($gpg_path)."
    fi

    basher_config_set SECRETS_MODE gpg
}

# Migriert gpg -> plain (Rückwechsel).
basher_secrets_decrypt() {
    command -v gpg > /dev/null 2>&1 || basher_die "gpg nicht gefunden - kann verschlüsselte Datei nicht lesen."
    [ "${SECRETS_MODE:-plain}" = "plain" ] && basher_die "SECRETS_MODE ist bereits 'plain'."

    local plain_path="$SECRETS_FILE" gpg_path="${SECRETS_FILE}.gpg"
    [ -f "$gpg_path" ] || basher_die "Keine verschlüsselte Secrets-Datei gefunden ($gpg_path)."
    [ -f "$plain_path" ] && basher_die "'$plain_path' existiert bereits - keine automatische Überschreibung."

    gpg -d --output "$plain_path" "$gpg_path" || basher_die "Entschlüsselung fehlgeschlagen (falsche Passphrase?)."
    chmod 600 "$plain_path"
    rm -f "$gpg_path"
    echo "basher: '$gpg_path' entschlüsselt nach '$plain_path'."

    basher_config_set SECRETS_MODE plain
}

# ===== lib/commands/config.sh =====
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

# ===== lib/commands/edit.sh =====
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

# ===== lib/commands/list.sh =====
# lib/commands/list.sh - basher list, s. Architekturplan 5.4
# Reine Textausgabe, minimal-tauglich (kein fzf nötig). Gruppierung erfolgt
# nach dem tatsächlichen Verzeichnis jedes Eintrags (nicht nur Top-Level),
# damit auch tief verschachtelte Kategorien (z.B. apps/kubernetes/kubeinit)
# sauber getrennt erscheinen statt in einer riesigen "apps:"-Gruppe zu landen.

cmd_list() {
    local manifest="$REPO_PATH/manifest.idx"
    [ -f "$manifest" ] || basher_die "Kein manifest.idx in '$REPO_PATH' gefunden - 'basher repo scan' ausführen."

    local key desc dir base current_dir="" count=0

    while IFS='|' read -r key desc; do
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue

        dir="$(dirname "$key")"
        base="$(basename "$key")"

        if [ "$dir" != "$current_dir" ]; then
            [ -n "$current_dir" ] && echo
            echo "$dir/"
            current_dir="$dir"
        fi

        if [ -n "$desc" ]; then
            printf '  %-40s %s\n' "$base" "$desc"
        else
            printf '  %s\n' "$base"
        fi
        count=$((count + 1))
    done < <(sort -t'|' -k1,1 "$manifest")

    if [ "$count" -eq 0 ]; then
        echo "basher: Keine Scripts im Manifest. 'basher new' oder 'basher repo scan' ausführen."
    fi
}

# ===== lib/commands/menu.sh =====
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

# ===== lib/commands/new.sh =====
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

# ===== lib/commands/repo.sh =====
# lib/commands/repo.sh - basher repo scan|set|sync, s. 3.3/3.5 + scan (Ergänzung)

cmd_repo() {
    local action="${1:-}"
    [ $# -gt 0 ] && shift

    case "$action" in
        scan)
            basher_manifest_scan "${1:-$REPO_PATH}"
            ;;
        sync)
            basher_repo_sync "$REPO_PATH"
            ;;
        set)
            [ $# -ge 1 ] || basher_die "Nutzung: basher repo set <pfad>"
            basher_config_set REPO_PATH "$1"
            echo "basher: REPO_PATH gesetzt auf '$1'"
            ;;
        "")
            basher_die "Nutzung: basher repo <scan|set|sync> [Argumente]"
            ;;
        *)
            basher_die "Unbekannte repo-Aktion: '$action' (scan|set|sync)"
            ;;
    esac
}

# ===== lib/commands/run.sh =====
# lib/commands/run.sh - basher run <name-or-path> [--repo <owner/repo>] [-- Argumente], s. 5.5

cmd_run() {
    local query="" repo_ref="${BASHER_REPO:-}"
    local -a script_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --repo)
                shift
                [ "$#" -ge 1 ] || basher_die "Nutzung: --repo <owner/repo>"
                repo_ref="$1"
                shift
                ;;
            --)
                shift
                script_args=("$@")
                break
                ;;
            *)
                if [ -z "$query" ]; then
                    query="$1"
                    shift
                else
                    script_args=("$@")
                    break
                fi
                ;;
        esac
    done

    [ -n "$query" ] || basher_die "Nutzung: basher run <name-or-path> [--repo <owner/repo>] [-- Argumente]"

    if [ -n "$repo_ref" ]; then
        basher_run_remote "$repo_ref" "$query" "${script_args[@]}"
    else
        basher_run_local "$query" "${script_args[@]}"
    fi
}

basher_run_local() {
    local query="$1"
    shift
    local relpath
    relpath="$(basher_manifest_resolve "$REPO_PATH" "$query")"
    [ -n "$relpath" ] || basher_die "Kein Script für '$query' gefunden oder Auswahl abgebrochen (s. 'basher list')."

    local script_path="$REPO_PATH/$relpath"
    [ -f "$script_path" ] || basher_die "'$script_path' existiert nicht (Manifest evtl. veraltet - 'basher repo scan' ausführen)."

    basher_secrets_load
    bash "$script_path" "$@"
}

basher_run_remote() {
    local repo_ref="$1" query="$2"
    shift 2

    command -v curl > /dev/null 2>&1 || basher_die "curl wird für den Remote-Modus benötigt."

    local tmp_dir branch
    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" EXIT

    branch="$(basher_remote_fetch "$repo_ref" "manifest.idx" "$tmp_dir/manifest.idx")" || \
        basher_die "Kein manifest.idx im Root von '$repo_ref' gefunden (main/master geprüft) - das scheint kein gültiger basher-Script-Store zu sein."

    local relpath
    relpath="$(basher_manifest_resolve "$tmp_dir" "$query")"
    [ -n "$relpath" ] || basher_die "Kein Script für '$query' in '$repo_ref' gefunden oder Auswahl abgebrochen."

    local script_tmp="$tmp_dir/script.sh"
    basher_remote_fetch_branch "$repo_ref" "$relpath" "$script_tmp" "$branch" || \
        basher_die "Konnte '$relpath' nicht von '$repo_ref' ($branch) laden."

    basher_secrets_load
    bash "$script_tmp" "$@"
}

# ===== lib/commands/secrets.sh =====
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

# ===== lib/commands/tmp.sh =====
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

# ===== lib/commands/version.sh =====
# lib/commands/version.sh - kleiner Diagnose-Befehl, v.a. um den Dispatcher
# (bin/basher, s. 1.4) end-to-end testen zu können, solange new/tmp/edit/... etc.
# noch nicht existieren.

cmd_version() {
    echo "basher 0.1.0-dev (Grundgerüst)"
    echo "INSTALL_MODE: ${INSTALL_MODE:-nicht gesetzt}"
    echo "REPO_PATH:    ${REPO_PATH:-}"
    echo "Config-Datei: ${BASHER_CONFIG_FILE:-}"
}

# ===== Dispatcher (entspricht bin/basher, s. 1.4) =====
basher_config_load

if [ "$#" -gt 0 ]; then
    cmd="cmd_$1"
    shift
else
    cmd="cmd_menu"
fi

if declare -f "$cmd" > /dev/null 2>&1; then
    "$cmd" "$@"
else
    echo "basher: Unbekannter Befehl '${cmd#cmd_}'" >&2
    available="$(compgen -A function | grep '^cmd_' | sed 's/^cmd_//' | sort | tr '\n' ' ')"
    echo "Verfügbare Befehle: $available" >&2
    exit 1
fi
