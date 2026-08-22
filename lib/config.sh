#!/usr/bin/env bash
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
