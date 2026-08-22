#!/usr/bin/env bash
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
    [ -n "$relpath" ] || basher_die "Kein eindeutiges Script für '$query' gefunden (s. 'basher list')."

    local script_path="$REPO_PATH/$relpath"
    [ -f "$script_path" ] || basher_die "'$script_path' existiert nicht (Manifest evtl. veraltet - 'basher repo scan' ausführen)."

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
    [ -n "$relpath" ] || basher_die "Kein eindeutiges Script für '$query' in '$repo_ref' gefunden."

    local script_tmp="$tmp_dir/script.sh"
    basher_remote_fetch_branch "$repo_ref" "$relpath" "$script_tmp" "$branch" || \
        basher_die "Konnte '$relpath' nicht von '$repo_ref' ($branch) laden."

    bash "$script_tmp" "$@"
}
