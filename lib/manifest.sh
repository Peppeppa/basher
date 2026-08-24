#!/usr/bin/env bash
# lib/manifest.sh - manifest.idx lesen/schreiben, s. Architekturplan 3.6

BASHER_MANIFEST_HEADER="# basher-manifest v1"

basher_manifest_path() {
    printf '%s/manifest.idx\n' "${1%/}"
}

# Normalisiert einen Manifest-Eintrag auf einen Pfad relativ zum Repo. Das
# hält auch Manifeste nutzbar, die mit einer älteren Version und einem
# REPO_PATH mit abschließendem Slash als absolute Pfade geschrieben wurden.
basher_manifest_relpath() {
    local repo_path="${1%/}" path="$2" relpath
    case "$path" in
        "$repo_path"/*)
            relpath="${path#"$repo_path"/}"
            # Fängt doppelte Trenner an der Repo-Grenze ab, die ältere
            # Versionen bei einem REPO_PATH mit abschließendem Slash erzeugten.
            while [[ "$relpath" == /* ]]; do relpath="${relpath#/}"; done
            printf '%s\n' "$relpath"
            ;;
        *) printf '%s\n' "$path" ;;
    esac
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
    relpath="$(basher_manifest_relpath "$repo_path" "$script_path")"

    tmp="$(mktemp)"
    awk -v rp="$relpath" -v desc="$description" -v root="${repo_path%/}/" -F'|' '
        BEGIN { OFS="|"; found=0 }
        /^#/ { print; next }
        NF==0 { next }
        {
            stored=$1
            if (index(stored, root) == 1) {
                stored=substr(stored, length(root) + 1)
                sub(/^\/+/, "", stored)
            }
        }
        stored == rp { print rp, desc; found=1; next }
        { print }
        END { if (!found) print rp, desc }
    ' "$manifest" > "$tmp" && mv "$tmp" "$manifest"
}

basher_manifest_get_description() {
    local repo_path="$1" relpath="$2" manifest
    manifest="$(basher_manifest_path "$repo_path")"
    [ -f "$manifest" ] || { echo ""; return 0; }
    local key desc normalized
    while IFS='|' read -r key desc; do
        normalized="$(basher_manifest_relpath "$repo_path" "$key")"
        if [ "$normalized" = "$relpath" ]; then
            printf '%s\n' "$desc"
            return 0
        fi
    done < "$manifest"
    echo ""
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
        key="$(basher_manifest_relpath "$repo_path" "$key")"
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
    local repo_path="${1%/}"
    [ -d "$repo_path" ] || basher_die "'$repo_path' existiert nicht."

    basher_manifest_ensure "$repo_path"
    local manifest
    manifest="$(basher_manifest_path "$repo_path")"

    local found_file rel
    local -A on_disk=()
    while IFS= read -r -d '' found_file; do
        rel="$(basher_manifest_relpath "$repo_path" "$found_file")"
        on_disk["$rel"]=1
    done < <(find "$repo_path" -type f -name '*.sh' -not -path '*/.*' -print0)

    local key desc
    local -A existing_desc=()
    while IFS='|' read -r key desc; do
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue
        key="$(basher_manifest_relpath "$repo_path" "$key")"
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
