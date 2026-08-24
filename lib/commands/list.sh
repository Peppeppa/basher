#!/usr/bin/env bash
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
        key="$(basher_manifest_relpath "$REPO_PATH" "$key")"

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
