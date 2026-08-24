#!/usr/bin/env bash
# lib/config.sh - Config laden, Defaults setzen, lesen/schreiben
#
# Siehe Architekturplan Abschnitt 2. Format: Bash-kompatible KEY=VALUE-Datei,
# direkt sourcebar. Schreibzugriffe quotieren Werte mit printf %q, damit
# Sonderzeichen nicht ausgewertet werden (kein externer Parser nötig).

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

# Kurze, für den interaktiven Walkthrough gedachte Erklärung pro Key.
basher_config_hint() {
    case "$1" in
        REPO_PATH)         echo "Lokaler Pfad zu deinem Script-Repo. Du kannst hier auch eine Git-URL (https://... oder git@...) eingeben - wird dann automatisch geklont bzw. als Remote verknüpft." ;;
        EDITOR_CMD)        echo "Editor-Override. Leer lassen, um automatisch \$EDITOR bzw. nvim/vim/vi zu verwenden." ;;
        TMP_DIR)           echo "Ablageort für Wegwerf-Scripts ('basher tmp'). Landet nie im Script-Repo." ;;
        AUTO_SYNTAX_CHECK) echo "Prüft Tmp-Scripts vor der Ausführung mit 'bash -n' (nur Warnung, kein Blocker). true/false." ;;
        AUTO_COMMIT)       echo "Committet nach 'new'/'edit' automatisch lokal (und bei SYNC_MODE=auto zusätzlich automatisch push). true/false." ;;
        SYNC_MODE)         echo "'auto' synchronisiert Git automatisch (pull+push), 'pro' zeigt nur den Status und überlässt dir die Kontrolle." ;;
        SECRETS_MODE)      echo "'plain' speichert Secrets im Klartext, 'gpg' verschlüsselt sie. Wechsel jederzeit über 'basher secrets encrypt/decrypt'." ;;
        SECRETS_FILE)      echo "Pfad zur Secrets-Datei (Klartext-Variante; im gpg-Modus wird automatisch .gpg angehängt)." ;;
        *)                 echo "" ;;
    esac
}

basher_config_write_defaults() {
    mkdir -p "$BASHER_CONFIG_DIR"
    {
        echo "# basher config - siehe docs/architecture.md Abschnitt 2.2"
        local key
        for key in "${BASHER_DEFAULT_KEYS[@]}"; do
            printf '%s=%q\n' "$key" "$(basher_config_default "$key")"
        done
    } > "$BASHER_CONFIG_FILE"
}

# Validiert Werte für Keys mit festem Wertebereich (Enum/Bool). Freitext-Keys
# (Pfade, URLs, ...) werden nicht eingeschränkt. Bei Ungültigkeit landet die
# Begründung in BASHER_CONFIG_VALIDATE_MSG, Rückgabewert 1.
basher_config_validate() {
    local key="$1" value="$2"
    if ! [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        BASHER_CONFIG_VALIDATE_MSG="Ungültiger Config-Key '$key' (erwartet: gültiger Bash-Variablenname)"
        return 1
    fi
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
            printf '%s=%q\n' "$key" "$(basher_config_default "$key")" >> "$BASHER_CONFIG_FILE"
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
    [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || basher_die "Ungültiger Config-Key '$key'."
    printf '%s\n' "${!key:-}"
}

# Setzt eine Bash-Zuweisung in einer Datei, ohne den Wert selbst als Code zu
# interpretieren. printf %q ist Bash-intern und bleibt damit minimal-tauglich.
basher_assignment_set_in_file() {
    local file="$1" key="$2" value="$3" tmp encoded found=false line
    printf -v encoded '%q' "$value"
    tmp="$(mktemp)"

    {
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" == "$key="* ]]; then
                printf '%s=%s\n' "$key" "$encoded"
                found=true
            else
                printf '%s\n' "$line"
            fi
        done < "$file"
        [ "$found" = "true" ] || printf '%s=%s\n' "$key" "$encoded"
    } > "$tmp" && mv "$tmp" "$file"
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

    basher_assignment_set_in_file "$BASHER_CONFIG_FILE" "$key" "$value"

    declare -g "$key=$value"
}
