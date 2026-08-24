#!/usr/bin/env bash
# lib/repo.sh - Git-Interaktion für REPO_PATH, s. Architekturplan 3.5

basher_repo_is_git() {
    local repo_path="$1"
    [ -d "$repo_path/.git" ]
}

# Erkennt, ob eine Eingabe eine Git-URL ist (https://, git://, ssh://, oder
# das kurze git@host:pfad-Format) statt eines lokalen Pfads.
basher_looks_like_git_url() {
    case "$1" in
        https://*|http://*|git://*|ssh://*|git@*) return 0 ;;
        *) return 1 ;;
    esac
}

# Konvertiert zwischen https://host/pfad(.git) und git@host:pfad(.git).
# Gibt die Original-URL unverändert zurück, falls das Format nicht erkannt
# wird (z.B. schon ssh:// oder ein exotisches Schema) - lieber unverändert
# lassen als etwas Falsches zu erzeugen.
basher_git_url_to_ssh() {
    local url="$1"
    case "$url" in
        https://*|http://*)
            local rest host path
            rest="${url#*://}"
            host="${rest%%/*}"
            path="${rest#*/}"
            printf 'git@%s:%s\n' "$host" "$path"
            ;;
        *)
            printf '%s\n' "$url"
            ;;
    esac
}

basher_git_url_to_https() {
    local url="$1"
    case "$url" in
        git@*)
            local rest host path
            rest="${url#git@}"
            host="${rest%%:*}"
            path="${rest#*:}"
            printf 'https://%s/%s\n' "$host" "$path"
            ;;
        *)
            printf '%s\n' "$url"
            ;;
    esac
}

# Zentrale Logik für 'basher repo set' UND den Config-Walkthrough (s.
# lib/commands/config.sh) - eine Eingabe kann ein lokaler Pfad ODER eine
# Git-URL sein:
#   - lokaler Pfad: setzt nur REPO_PATH (bisheriges Verhalten, unverändert).
#   - Git-URL: fragt (sofern nicht per protocol-Parameter vorgegeben) ob
#     SSH oder HTTPS genutzt werden soll, konvertiert bei Bedarf, setzt
#     REPO_URL, und klont nach REPO_PATH (falls dort noch nichts liegt)
#     bzw. aktualisiert den 'origin'-Remote eines bereits vorhandenen
#     Git-Repos - klont/überschreibt nie ungefragt in ein nicht-leeres,
#     nicht-Git-Verzeichnis hinein.
basher_repo_set_smart() {
    local input="$1" protocol="${2:-}"

    if ! basher_looks_like_git_url "$input"; then
        basher_config_set REPO_PATH "$input"
        echo "basher: REPO_PATH gesetzt auf '$input'"
        return 0
    fi

    command -v git > /dev/null 2>&1 || basher_die "git wird benötigt, um eine Repo-URL zu nutzen."

    if [ -z "$protocol" ]; then
        local choice
        read -r -p "SSH oder HTTPS für Push/Pull nutzen? [ssh/$(basher_bold https)]: " choice
        case "$choice" in
            ssh|SSH) protocol="ssh" ;;
            *) protocol="https" ;;
        esac
    fi

    local final_url
    if [ "$protocol" = "ssh" ]; then
        final_url="$(basher_git_url_to_ssh "$input")"
    else
        final_url="$(basher_git_url_to_https "$input")"
    fi

    local default_target
    default_target="$(basher_config_default REPO_PATH)"
    local target
    read -r -p "Zielpfad [$(basher_bold "$default_target")]: " target
    [ -z "$target" ] && target="$default_target"

    if [ -d "$target" ] && [ "$(ls -A "$target" 2>/dev/null)" ]; then
        if basher_repo_is_git "$target"; then
            if git -C "$target" remote | grep -qx origin; then
                git -C "$target" remote set-url origin "$final_url" || basher_die "Konnte Remote-URL nicht setzen."
            else
                git -C "$target" remote add origin "$final_url" || basher_die "Konnte Remote 'origin' nicht anlegen."
            fi
            echo "basher: Remote 'origin' von '$target' auf '$final_url' gesetzt."
        else
            basher_die "'$target' existiert bereits, ist nicht leer und kein Git-Repo - breche ab, statt etwas zu überschreiben. Wähle einen anderen REPO_PATH oder räume manuell auf."
        fi
    else
        mkdir -p "$(dirname "$target")"
        git clone "$final_url" "$target" || basher_die "Klonen von '$final_url' fehlgeschlagen."
        echo "basher: '$final_url' nach '$target' geklont."
    fi

    basher_config_set REPO_PATH "$target"
    basher_config_set REPO_URL "$final_url"
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
