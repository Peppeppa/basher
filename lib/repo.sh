#!/usr/bin/env bash
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
