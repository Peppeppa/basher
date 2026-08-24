#!/usr/bin/env bash
# build-minimal.sh - erzeugt minimal/basher-minimal.sh aus den lib/*.sh-Quellen.
#
# Die lib/*.sh-Dateien bleiben die einzige Quelle der Wahrheit (s. Architekturplan
# 1.2/1.4/7). Diese Datei wird bei Bedarf neu generiert statt von Hand gepflegt,
# damit die Minimal- und die Voll-Variante nie auseinanderlaufen. Bündelt alle
# Funktionsdefinitionen physisch in eine Datei (keine lokalen sudo-Rechte,
# keine externen Pakete außer bash/curl nötig), damit sie per
# 'curl -fsSL <raw-url> | bash -s -- <command>' direkt lauffähig ist.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/minimal/basher-minimal.sh"
mkdir -p "$ROOT/minimal"

LIB_FILES=(config.sh checks.sh core.sh repo.sh manifest.sh remote.sh secrets.sh)

{
    echo '#!/usr/bin/env bash'
    echo '# basher-minimal.sh - AUTOMATISCH GENERIERT aus lib/*.sh, s. build-minimal.sh'
    echo '# NICHT VON HAND BEARBEITEN - Änderungen gehen bei der nächsten Generierung'
    echo '# verloren. Quelle der Wahrheit: lib/*.sh in diesem Repo.'
    echo '#'
    echo "# Generiert am $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo 'set -uo pipefail'
    echo "trap 'exit 1' TERM  # s. Kommentar zu basher_die in lib/checks.sh"
    echo

    for f in "${LIB_FILES[@]}"; do
        [ -f "$ROOT/lib/$f" ] || { echo "build-minimal.sh: lib/$f fehlt" >&2; exit 1; }
        echo "# ===== lib/$f ====="
        tail -n +2 "$ROOT/lib/$f"
        echo
    done

    for f in "$ROOT"/lib/commands/*.sh; do
        echo "# ===== lib/commands/$(basename "$f") ====="
        tail -n +2 "$f"
        echo
    done

    cat << 'DISPATCH_EOF'
# ===== Dispatcher (entspricht bin/basher, s. 1.4) =====
basher_config_load

if [ "$#" -gt 0 ]; then
    cmd="cmd_$1"
    shift
else
    cmd="cmd_menu"
fi

if declare -f "$cmd" > /dev/null 2>&1; then
    "$cmd" "$@"
else
    echo "basher: Unbekannter Befehl '${cmd#cmd_}'" >&2
    available="$(compgen -A function | grep '^cmd_' | sed 's/^cmd_//' | sort | tr '\n' ' ')"
    echo "Verfügbare Befehle: $available" >&2
    exit 1
fi
DISPATCH_EOF
} > "$OUT"

chmod +x "$OUT"
echo "basher: Minimal-Bundle erzeugt -> $OUT ($(wc -l < "$OUT" | tr -d ' ') Zeilen, $(wc -c < "$OUT" | tr -d ' ') Bytes)"
