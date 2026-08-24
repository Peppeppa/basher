#!/usr/bin/env bash
# install.sh - basher installieren, s. Architekturplan 5.8
#
# Installiert einen dünnen Wrapper nach ~/.local/bin/basher, der per exec auf
# den absoluten Pfad DIESES Repos zeigt (kein sudo, kein systemweiter Eingriff,
# kein Symlink - vermeidet damit jede Symlink-Auflösungs-Problematik in
# bin/basher selbst). Default ist die Vollinstallation (wer klont, will
# vermutlich das komplette Erlebnis) - --minimal für die schlanke Variante
# ohne fzf-Abhängigkeit. Bei Vollinstallation läuft im Anschluss automatisch
# der Config-Walkthrough (s. lib/commands/config.sh).

set -uo pipefail

BASHER_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BIN_DIR="$HOME/.local/bin"

usage() {
    echo "Nutzung: install.sh [--minimal|--full]" >&2
    echo "  Ohne Option: Vollinstallation (Default)." >&2
    exit 1
}

mode="full"
for arg in "$@"; do
    case "$arg" in
        --minimal) mode="minimal" ;;
        --full) mode="full" ;;
        -h|--help) usage ;;
        *) echo "basher: Unbekannte Option: $arg" >&2; usage ;;
    esac
done

echo "basher: Installiere im Modus '$mode' ..."

# --- bin/basher ausführbar machen + Wrapper in PATH einrichten ---
chmod +x "$BASHER_REPO_ROOT/bin/basher"
mkdir -p "$INSTALL_BIN_DIR"

cat > "$INSTALL_BIN_DIR/basher" << WRAPPER_EOF
#!/usr/bin/env bash
exec "$BASHER_REPO_ROOT/bin/basher" "\$@"
WRAPPER_EOF
chmod +x "$INSTALL_BIN_DIR/basher"

echo "basher: Wrapper installiert -> $INSTALL_BIN_DIR/basher (zeigt auf $BASHER_REPO_ROOT/bin/basher)"

case ":$PATH:" in
    *":$INSTALL_BIN_DIR:"*) : ;;
    *)
        echo "basher: Hinweis - '$INSTALL_BIN_DIR' ist nicht in deinem PATH."
        echo "  Füge z.B. in ~/.bashrc oder ~/.zshrc hinzu:"
        echo "  export PATH=\"$INSTALL_BIN_DIR:\$PATH\""
        ;;
esac

# --- Voll-Modus: fzf pruefen/installieren ---
if [ "$mode" = "full" ]; then
    if command -v fzf > /dev/null 2>&1; then
        echo "basher: fzf bereits vorhanden."
    else
        echo "basher: fzf nicht gefunden, versuche Installation über erkannten Paketmanager ..."
        installed=0
        if command -v pacman > /dev/null 2>&1; then
            sudo pacman -S --noconfirm fzf && installed=1
        elif command -v apt > /dev/null 2>&1; then
            sudo apt install -y fzf && installed=1
        elif command -v dnf > /dev/null 2>&1; then
            sudo dnf install -y fzf && installed=1
        elif command -v brew > /dev/null 2>&1; then
            brew install fzf && installed=1
        fi

        if [ "$installed" -eq 1 ] && command -v fzf > /dev/null 2>&1; then
            echo "basher: fzf erfolgreich installiert."
        else
            echo "basher: Warnung - fzf konnte nicht automatisch installiert werden." >&2
            echo "  Bitte manuell installieren, sonst funktioniert 'basher menu' nicht." >&2
        fi
    fi
fi

# --- INSTALL_MODE in der Config setzen (nutzt basher selbst, keine Logik-Dopplung) ---
"$INSTALL_BIN_DIR/basher" config set INSTALL_MODE "$mode" > /dev/null

echo "basher: Installation abgeschlossen (INSTALL_MODE=$mode)."

if [ "$mode" = "full" ]; then
    echo
    "$INSTALL_BIN_DIR/basher" config
fi

echo "basher: Neue Shell starten oder 'source ~/.bashrc', dann 'basher version' zum Testen."
