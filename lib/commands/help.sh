#!/usr/bin/env bash
# lib/commands/help.sh - basher -h/--help (kurz) und basher help (ausführlich)

cmd_help() {
    cat << 'EOF'
basher - ein einfacher Bash-Script-Manager

Nutzung: basher <befehl> [argumente]

Scripts erstellen & bearbeiten:
  new [name] [--category pfad]    Neues Script in einem Unterordner anlegen
  tmp                             Temporäres Script anlegen, ausführen, danach löschen
  edit [name]                     Bestehendes Script bearbeiten

Scripts finden & ausführen:
  list                            Alle Scripts als Textliste
  menu                            Interaktives fzf-Menü (nur Vollinstallation)
  run <name> [--repo o/r] [-- args]
                                   Script ausführen, lokal oder aus fremdem GitHub-Repo

Konfiguration:
  config get|set|path|edit        Konfiguration lesen/ändern

Script-Repo:
  repo scan|set|sync

Secrets:
  secrets set|get|list|edit|encrypt|decrypt

Sonstiges:
  version                         Diagnose-Ausgabe
  help                             Ausführliche Hilfe mit Beispielen
  -h, --help                      Diese Übersicht
EOF
}

cmd_help_full() {
    cat << 'EOF'
basher - ein einfacher Bash-Script-Manager

Verwaltet, kategorisiert und führt eigene Bash-Scripts aus. Kategorisierung erfolgt über die
Ordnerstruktur eines konfigurierbaren Script-Repos. Läuft lokal installiert (mit optionalem
interaktivem fzf-Menü) oder minimal per curl-Pipe ohne jede Installation.

BEFEHLE

  new [name] [--category pfad]
      Neues Script anlegen. Ohne --category wird auch nach dem gewünschten
      Unterordner gefragt; eine leere Eingabe legt das Script im Repo-Root an.
      Beispiel: basher new backup --category apps/borg

  tmp
      Temporäres Script anlegen, im Editor öffnen, ausführen, danach löschen.
      Landet nie im Script-Repo.

  edit [name]
      Bestehendes Script bearbeiten. Ohne Namen im Voll-Modus per fzf-Picker.
      Name kann Basename oder voller Pfad sein, mit oder ohne .sh.

  list
      Alle Scripts als Textliste, gruppiert nach Verzeichnis.

  menu
      Interaktives fzf-Menü mit relativen Pfaden ab dem Script-Repo und
      Preview (nur Vollinstallation).
      Enter führt aus, Ctrl-E bearbeitet, Esc bricht ab.

  run <name> [--repo owner/repo] [-- argumente]
      Script ausführen, ohne es zu öffnen. Ohne --repo lokal aus dem konfigurierten
      Script-Repo, mit --repo ad-hoc aus einem beliebigen öffentlichen GitHub-Repo.
      Beispiel: basher run backup --repo someone/scripts -- --dry-run

  config get|set|path|edit
      Konfiguration lesen bzw. ändern. Ohne Argument (nur Vollinstallation):
      interaktiver Walkthrough mit Erklärung zu jeder Einstellung.

  repo scan [pfad]
      Erzeugt/aktualisiert das Manifest aus einer bestehenden Ordnerstruktur
      (neue Scripts ergänzen, verschwundene entfernen, Beschreibungen bleiben erhalten).

  repo set <pfad-oder-url> [--ssh|--https]
      Aktives Script-Repo wechseln. Bei einer Git-URL wird automatisch geklont
      bzw. der Remote aktualisiert, inkl. Abfrage/Konvertierung SSH <-> HTTPS.

  repo sync
      Git-Repo synchronisieren. Verhalten hängt von SYNC_MODE ab:
      auto = automatisch pull --rebase + push, pro = nur Status anzeigen.

  secrets set|get|list|edit|encrypt|decrypt
      Secrets verwalten. Landen automatisch als Umgebungsvariablen in per
      run/tmp ausgeführten Scripts. encrypt/decrypt wechseln zwischen
      Klartext und GPG-Verschlüsselung. Keys sind Bash-Variablennamen;
      Werte werden beim Speichern Bash-sicher quotiert.

  version
      Diagnose-Ausgabe: Version, Installationsmodus, Script-Repo-Pfad, Config-Pfad.

KONFIGURATION

  Liegt unter ~/.config/basher/config, wird beim ersten Full-Install automatisch
  über einen interaktiven Walkthrough eingerichtet (jederzeit erneut: basher config).
  Wichtige Keys: REPO_PATH, EDITOR_CMD, AUTO_COMMIT, SYNC_MODE, SECRETS_MODE.

DATEIEN

  ~/.config/basher/config              Konfiguration
  ~/.config/basher/secrets.env(.gpg)   Secrets
  <REPO_PATH>/manifest.idx             Verzeichnis aller Scripts im Script-Repo

Vollständige Architektur-Dokumentation: docs/architecture.md im basher-Repository.
EOF
}
