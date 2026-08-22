#!/usr/bin/env bash
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

    if [ "${#exact[@]}" -eq 1 ]; then
        printf '%s\n' "${exact[0]}"
        return 0
    elif [ "${#exact[@]}" -eq 0 ] && [ "${#partial[@]}" -eq 1 ]; then
        printf '%s\n' "${partial[0]}"
        return 0
    elif [ "${#exact[@]}" -gt 1 ] || [ "${#partial[@]}" -gt 1 ]; then
        echo "basher: Mehrdeutig - mehrere Treffer für '$query':" >&2
        printf '  %s\n' "${exact[@]}" "${partial[@]}" >&2
        return 1
    else
        return 1
    fi
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
