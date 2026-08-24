#!/usr/bin/env bash
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
