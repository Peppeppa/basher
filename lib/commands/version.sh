#!/usr/bin/env bash
# lib/commands/version.sh - kleiner Diagnose-Befehl, v.a. um den Dispatcher
# (bin/basher, s. 1.4) end-to-end testen zu können, solange new/tmp/edit/... etc.
# noch nicht existieren.

cmd_version() {
    echo "basher 0.1.0-dev (Grundgerüst)"
    echo "INSTALL_MODE: ${INSTALL_MODE:-nicht gesetzt}"
    echo "REPO_PATH:    ${REPO_PATH:-}"
    echo "Config-Datei: ${BASHER_CONFIG_FILE:-}"
}
