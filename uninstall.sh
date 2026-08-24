#!/usr/bin/env bash
# uninstall.sh - basher deinstallieren, s. Architekturplan 5.8
#
# Entfernt NUR den Tool-Wrapper (~/.local/bin/basher). Fragt separat und
# explizit nach, ob Config bzw. Secrets-Datei ebenfalls gelöscht werden
# sollen - Default ist in beiden Fällen "Behalten". Das Script-Repo
# (REPO_PATH) wird nie angefasst - das ist dein eigenes Repo, nicht basher's.

set -uo pipefail

INSTALL_BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/basher"
CONFIG_FILE="$CONFIG_DIR/config"

if [ -f "$INSTALL_BIN_DIR/basher" ]; then
    rm -f "$INSTALL_BIN_DIR/basher"
    echo "basher: Wrapper entfernt ($INSTALL_BIN_DIR/basher)."
else
    echo "basher: Kein Wrapper unter $INSTALL_BIN_DIR/basher gefunden - übersprungen."
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "basher: Keine Config gefunden - Deinstallation abgeschlossen."
    exit 0
fi

repo_path="$(awk -F'"' '/^REPO_PATH=/{print $2}' "$CONFIG_FILE")"
secrets_mode="$(awk -F'"' '/^SECRETS_MODE=/{print $2}' "$CONFIG_FILE")"
secrets_file_base="$(awk -F'"' '/^SECRETS_FILE=/{print $2}' "$CONFIG_FILE")"

# Tatsächlichen Pfad je nach Modus ermitteln (spiegelt basher_secrets_path()
# aus lib/secrets.sh) - uninstall.sh sourced die lib bewusst nicht, um auch
# bei kaputter Installation noch zu funktionieren, daher die kleine Dopplung.
if [ "$secrets_mode" = "gpg" ]; then
    secrets_file="${secrets_file_base}.gpg"
else
    secrets_file="$secrets_file_base"
fi

echo
[ -n "$repo_path" ] && echo "Dein Script-Repo bleibt unangetastet: $repo_path"

read -r -p "Config-Datei löschen ($CONFIG_FILE)? [j/N]: " del_config
case "$del_config" in
    j|J) rm -f "$CONFIG_FILE"; echo "basher: Config gelöscht." ;;
    *)   echo "basher: Config behalten." ;;
esac

if [ -n "$secrets_file" ] && [ -f "$secrets_file" ]; then
    read -r -p "Secrets-Datei löschen ($secrets_file)? [j/N]: " del_secrets
    case "$del_secrets" in
        j|J) rm -f "$secrets_file"; echo "basher: Secrets-Datei gelöscht." ;;
        *)   echo "basher: Secrets-Datei behalten." ;;
    esac
fi

rmdir --ignore-fail-on-non-empty "$CONFIG_DIR" 2>/dev/null || true

echo
echo "basher: Deinstallation abgeschlossen."
