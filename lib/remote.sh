#!/usr/bin/env bash
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
