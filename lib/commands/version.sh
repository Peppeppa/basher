#!/usr/bin/env bash
# lib/commands/version.sh - Versions- und Diagnose-Ausgabe.

cmd_version() {
    echo "basher 1.0.0"
    echo "INSTALL_MODE: ${INSTALL_MODE:-nicht gesetzt}"
    echo "REPO_PATH:    ${REPO_PATH:-}"
    echo "Config-Datei: ${BASHER_CONFIG_FILE:-}"
}
