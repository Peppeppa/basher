# basher

Ein kleiner, reiner Bash-Script-Manager fürs Terminal. Verwaltet, kategorisiert und führt eigene
Shell-Scripts aus – lokal mit einem interaktiven `fzf`-Menü, oder minimal per `curl`-Einzeiler auf
jedem Server ohne vorherige Installation.

## Features

- **Zwei Installationsmodi**: Minimal (nur `bash`/`curl`, kein `sudo`, keine Zusatzpakete) und Voll
  (mit `fzf`-Menü)
- **Kategorisierung über die Ordnerstruktur** deines eigenen Script-Repos
- **`new`/`tmp`**: neue Scripts anlegen (dauerhaft oder als Wegwerf-Script mit Ausführungs-Loop)
- **`edit`/`run`/`list`/`menu`**: bestehende Scripts bearbeiten, ausführen, durchsuchen
- **Mehrdeutige Namen**: bei mehreren Treffern gibt's eine Auswahl statt eines Fehlers
- **Git-Sync**: automatischer Pull+Push (`SYNC_MODE=auto`) oder rein manuelle Kontrolle (`=pro`)
- **Secrets**: einfache Bash-kompatible `KEY=VALUE`-Datei oder optional GPG-verschlüsselt
- **Ad-hoc-Ausführung** von Scripts aus einem beliebigen öffentlichen GitHub-Repo per `--repo`

## Installation

### Voll (lokal, mit Menü) – Default

```bash
git clone https://github.com/Peppeppa/basher.git
cd basher
./install.sh
```

Richtet einen Wrapper unter `~/.local/bin/basher` ein (kein `sudo`, kein Symlink), installiert
`fzf`, falls nicht schon vorhanden, und führt direkt im Anschluss durch die Einrichtung der
wichtigsten Einstellungen (`basher config`).

### Minimal (lokal installiert, ohne fzf)

```bash
git clone https://github.com/Peppeppa/basher.git
cd basher
./install.sh --minimal
```

Gleicher Wrapper unter `~/.local/bin/basher`, aber ohne `fzf`-Abhängigkeit – geeignet für Server,
auf denen kein interaktives Menü gebraucht wird.

### Ohne Installation (curl-Direktausführung, z. B. Headless-Server)

```bash
curl -fsSL https://raw.githubusercontent.com/Peppeppa/basher/main/minimal/basher-minimal.sh \
  | bash -s -- <befehl>
```

Läuft direkt aus dem Repo heraus, ganz ohne lokale Installation – ideal für einmalige Nutzung auf
einem fremden Server. Funktioniert auch gegen ein beliebiges anderes öffentliches Script-Repo:

```bash
curl -fsSL https://raw.githubusercontent.com/Peppeppa/basher/main/minimal/basher-minimal.sh \
  | bash -s -- run <script> --repo <anderer-user>/<script-repo>
```

## Befehle

| Befehl | Zweck |
|---|---|
| `basher new [name] [--category pfad]` | Neues Script anlegen (fragt ohne `--category` nach dem Unterordner) |
| `basher tmp` | Temporäres Script anlegen, ausführen, danach löschen |
| `basher edit [name]` | Bestehendes Script bearbeiten (fzf-Picker ohne Argument, Voll-Modus) |
| `basher list` | Alle Scripts als Textliste, gruppiert nach Verzeichnis |
| `basher menu` | Interaktives fzf-Menü mit repo-relativen Pfaden (Enter=ausführen, Ctrl-E=bearbeiten) |
| `basher run <name> [--repo owner/repo] [-- args]` | Script ausführen, lokal oder aus fremdem Repo |
| `basher config get\|set\|path\|edit` | Konfiguration lesen/ändern |
| `basher repo scan [pfad]` | Manifest aus vorhandener Ordnerstruktur (neu) erzeugen |
| `basher repo set <pfad>` | Aktives Script-Repo wechseln |
| `basher repo sync` | Git-Repo synchronisieren (`SYNC_MODE`-abhängig) |
| `basher secrets set\|get\|list\|edit\|encrypt\|decrypt` | Secrets verwalten |
| `basher version` | Diagnose-Ausgabe |
| `basher help` | Ausführliche Hilfe mit Beispielen |
| `basher -h` / `--help` | Kurzübersicht der Befehle |

`basher new`/`edit`/`tmp` erkennen automatisch den Editor (`$EDITOR` → `nvim` → `vim` → `vi`,
override via `EDITOR_CMD`).

Bei `basher new` wird ohne `--category` nach dem gewünschten Unterordner innerhalb des
Script-Repos gefragt. Eine leere Eingabe legt das Script bewusst direkt im Repo-Root an.

## Konfiguration

Liegt unter `~/.config/basher/config`, wird beim ersten Start automatisch mit Defaults angelegt.

| Key | Bedeutung | Default |
|---|---|---|
| `INSTALL_MODE` | `minimal` oder `full`, von `install.sh` gesetzt | – |
| `REPO_PATH` | Lokaler Pfad zum Script-Repo | `~/.local/share/basher/scripts` |
| `REPO_URL` | Remote-URL des Script-Repos | leer |
| `EDITOR_CMD` | Editor-Override | leer |
| `TMP_DIR` | Ablage für `tmp`-Scripts | `${TMPDIR:-/tmp}/basher` |
| `AUTO_SYNTAX_CHECK` | `bash -n` vor Ausführung eines Tmp-Scripts | `true` |
| `AUTO_COMMIT` | Automatischer Git-Commit nach `new`/`edit` | `false` |
| `SYNC_MODE` | `auto` (Pull+Push automatisch) oder `pro` (nur Status, manuell) | `auto` |
| `SECRETS_MODE` | `plain` oder `gpg` | `plain` |
| `SECRETS_FILE` | Pfad zur Secrets-Datei | `~/.config/basher/secrets.env` |

## Script-Repo

Dein Script-Repo ist bewusst getrennt vom basher-Tool selbst. Kategorisierung erfolgt rein über
die Ordnerstruktur – ein `manifest.idx` im Root listet alle Scripts (Pfad + Kurzbeschreibung) und
wird automatisch von `new`/`edit`/`repo scan` gepflegt.

Für ein bereits bestehendes, lokales Script-Repo:

```bash
basher config set REPO_PATH /pfad/zu/deinen/scripts
basher repo scan
```

Zum Klonen eines Script-Repos von GitHub reicht die HTTPS-URL – `basher` fragt automatisch, ob SSH
oder HTTPS für künftige Push/Pull-Operationen genutzt werden soll (Default fett markiert),
konvertiert bei Bedarf, und fragt nach dem gewünschten Zielpfad (Default `~/.local/share/basher/scripts`):

```bash
basher repo set https://github.com/<user>/<scripts-repo>.git
```

## Secrets

```bash
basher secrets set API_TOKEN irgendwas
basher secrets list      # nur Key-Namen, keine Werte
basher secrets encrypt   # Wechsel zu GPG-verschlüsselt (symmetrisch)
```

Secrets landen automatisch als Umgebungsvariablen in jedem per `run`/`tmp` ausgeführten Script.
Config und Secrets bleiben bewusst einfache, mit Bash `source` ladbare `KEY=VALUE`-Dateien, damit
auch die Minimalversion ohne Parser oder Zusatzpakete funktioniert. Von basher geschriebene Werte
werden mit Bash-`printf %q` sicher quotiert; Keys müssen gültige Bash-Variablennamen sein.
Bei manueller Bearbeitung über `config edit` bzw. `secrets edit` muss der Inhalt entsprechend
gültige Bash-Syntax bleiben.

## Deinstallation

```bash
./uninstall.sh
```

Entfernt nur den Wrapper. Config und Secrets werden separat und explizit abgefragt (Default:
behalten). Dein Script-Repo wird nie angefasst.

## Entwicklung

- `lib/*.sh` ist die einzige Quelle der Wahrheit für alle Befehle (`lib/commands/*.sh`)
- `minimal/basher-minimal.sh` ist **generiert**, nicht von Hand bearbeiten – nach Änderungen an
  `lib/*.sh`:
  ```bash
  ./build-minimal.sh
  ```
- Architektur- und Design-Entscheidungen: [`docs/architecture.md`](docs/architecture.md)
