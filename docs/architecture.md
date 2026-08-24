# basher – Architektur-Dokumentation (v1.0)

Dieses Dokument beschreibt die implementierte Architektur von basher. Referenznummern dienen der
Verweisbarkeit zwischen Code, README und dieser Doku.

---

## 1. Grundarchitektur

### 1.1 Trennung: Tool-Repo vs. Script-Store
`basher` (das Tool) und die eigentlichen `.sh`-Scripts liegen in getrennten Repos/Verzeichnissen.
Das basher-Repo enthält nur Code des Managers (`install.sh`, `uninstall.sh`, `bin/`, `lib/`). Wo
Nutzer-Scripts gespeichert werden, ist reine Konfigurationssache (siehe 3).

### 1.2 Installationsmodi
- **Minimal**: einzelnes, self-contained Bash-Script (`minimal/basher-minimal.sh`), keine externen
  Pakete außer `curl`/`bash` selbst. Läuft per `curl -fsSL <raw-url> | bash -s -- <command>` ohne
  vorherige Installation, oder lokal installiert via `install.sh --minimal`.
- **Voll**: lokaler Clone, modulare `lib/*.sh`, nutzt `fzf` für das interaktive Menü.
- `install.sh` installiert per Default die Vollversion; `install.sh --minimal` für die schlanke
  Variante ohne `fzf`-Abhängigkeit. `--full` ist als expliziter Alias ebenfalls gültig.

### 1.3 Editor & Ausführung
Fallback-Kette statt hartkodiertem Editor: `EDITOR_CMD` (Config) → `$EDITOR` → `nvim` → `vim` →
`vi` (`basher_resolve_editor` in `lib/core.sh`). Vor Ausführung eines frisch bearbeiteten
Tmp-Scripts: `bash -n <script>` als Syntax-Check (Warnung, kein Blocker), danach Rückfrage ob
ausgeführt werden soll (kein automatisches Blind-Execute).

### 1.4 Erweiterbarkeit: Command-Dispatcher statt if/elif-Kette
Jeder Subcommand ist eine eigene Funktion `cmd_<name>()` in einer eigenen Datei unter
`lib/commands/` (Voll-Modus) bzw. im gleichen Namensschema innerhalb der in eine Datei gebündelten
Minimal-Variante (s. 1.2/7). `bin/basher` selbst enthält keine Befehlslogik, sondern nur den
Dispatcher: Bibliotheken laden, alle `lib/commands/*.sh` sourcen, dann den passenden `cmd_*`
auflösen und aufrufen. Ohne Argument wird `cmd_menu` aufgerufen. Ist der Befehl unbekannt, listet
`bin/basher` alle tatsächlich vorhandenen `cmd_*`-Funktionen auf, statt nur stumm zu scheitern.

Ein neuer Befehl bedeutet: neue Datei in `lib/commands/`, Funktion `cmd_foo()` schreiben, fertig –
kein Anfassen von `bin/basher`. Minimal- und Voll-Variante nutzen dasselbe Namensschema (`cmd_*`),
auch wenn der Minimal-Code physisch in einer Datei gebündelt ist (`build-minimal.sh` generiert
`minimal/basher-minimal.sh` aus denselben `lib/*.sh`-Quellen, s. 7).

### 1.5 Guard-Funktionen statt verstreuter Fehlerbehandlung
Zentrale Guard-Funktionen in `lib/checks.sh` prüfen Vorbedingungen und geben bei Nichterfüllung
eine klare, handlungsanweisende Meldung aus statt einfach zu crashen:

- `require_full_install` – bricht mit Meldung ab, falls `INSTALL_MODE != full` (s. 2.2, 5.4)
- `require_fzf` – bricht mit Meldung ab, falls `fzf` trotz Vollinstallation fehlt (z. B. manuell
  deinstalliert)
- `require_manifest <repo-pfad>` – bricht mit Meldung ab, falls kein `manifest.idx` im Root
  gefunden wird (s. 3.4/3.6)
- `require_gpg` – **Sonderfall, kein Abbruch:** gibt nur den Verfügbarkeitsstatus von `gpg` zurück
  (wahr/falsch). Fehlendes `gpg` ist laut 4.3 kein Fehler, sondern löst einen stillen Fallback auf
  `SECRETS_MODE=plain` aus – der Aufrufer entscheidet, was er mit dem Ergebnis macht.

Jeder Befehl ruft am Anfang die passenden Guards auf statt eigene Ad-hoc-Prüfungen zu bauen – neue
Subcommands bekommen Fehlerbehandlung so ohne Zusatzaufwand.

### 1.6 Zentraler Fehlerabbruch: `basher_die`
`basher_die` (`lib/checks.sh`) gibt eine Meldung auf stderr aus und beendet den gesamten
Prozess – auch wenn der Aufruf tief in einer Command-Substitution steckt (z. B.
`editor="$(basher_resolve_editor)"`). Ein einfaches `exit` würde in diesem Fall nur die Subshell
der Substitution beenden, das Hauptskript liefe mit einem leeren Rückgabewert weiter. Deshalb
sendet `basher_die` zusätzlich `kill -s TERM "$$"` (referenziert laut Bash-Semantik auch innerhalb
von Subshells immer die PID des äußersten Skripts); `bin/basher` sowie das generierte
Minimal-Bundle fangen `TERM` per Trap ab (`trap 'exit 1' TERM`) und terminieren zuverlässig.

### 1.7 Einheitliche Default-Hervorhebung in Prompts
`basher_bold` (`lib/core.sh`) umschließt Text mit ANSI-Bold-Codes. Überall dort, wo ein Prompt
einen Wert zeigt, der bei leerer Eingabe (Enter) übernommen wird, wird dieser Wert fett dargestellt
(`KEY [Default]:`) statt zusätzlich in Textform erklärt zu werden (z. B. statt „Enter=https“) –
konsistent über Config-Walkthrough, `repo set` und `edit`.

---

## 2. Konfiguration

### 2.1 Speicherort & Format
`~/.config/basher/config` – einfache `KEY="value"`-Datei, direkt in Bash sourcebar (kein
YAML/JSON-Parser nötig → Minimal-Modus-kompatibel).

### 2.2 Config-Schema

| Key | Beschreibung | Default |
|---|---|---|
| `INSTALL_MODE` | `minimal` oder `full` – von `install.sh` gesetzt, zur Laufzeit von Guards geprüft (s. 1.5) | wird bei Installation verpflichtend gesetzt |
| `REPO_PATH` | Lokaler Pfad zum Script-Repo | `~/.local/share/basher/scripts` |
| `REPO_URL` | Git-URL des Script-Repos, automatisch gesetzt beim Klonen/Verknüpfen (s. 3.3) – kein direktes Walkthrough-Feld | leer |
| `EDITOR_CMD` | Override für Editor | leer (→ Fallback-Kette 1.3) |
| `TMP_DIR` | Ablageort temporärer Scripts (Sicherheitsnetz, s. 5.1) | `${TMPDIR:-/tmp}/basher` |
| `AUTO_SYNTAX_CHECK` | `bash -n` vor Ausführung eines Tmp-Scripts | `true` |
| `AUTO_COMMIT` | nach `new`/`edit` lokal automatisch committen | `false` (wird bei `install.sh` abgefragt, s. 5.8) |
| `SYNC_MODE` | Verhalten von `repo sync`: `auto` oder `pro` (s. 3.5) | `auto` |
| `SECRETS_MODE` | `plain` oder `gpg` | `plain` |
| `SECRETS_FILE` | Pfad zur Secrets-Datei (Klartext-Pfad; im `gpg`-Modus wird `.gpg` angehängt, s. 4) | `~/.config/basher/secrets.env` |

Werte mit festem Wertebereich (`AUTO_SYNTAX_CHECK`, `AUTO_COMMIT`, `SYNC_MODE`, `SECRETS_MODE`,
`INSTALL_MODE`) werden bei `basher config set` validiert; ungültige Werte werden abgelehnt.

### 2.3 Erststart-Verhalten
- `install.sh` (Default: Vollinstallation) stößt am Ende der Installation den interaktiven
  Walkthrough (s. 2.4) direkt an – nicht erst beim ersten `basher`-Aufruf, damit die Config nicht
  von einem zufälligen ersten Befehl abhängt. Jederzeit erneut aufrufbar über `basher config`.
  `install.sh --minimal` sowie jeder `bin/basher`-Aufruf ohne vorhandene Config legen sie
  ansonsten still mit Defaults an (`basher_config_load`) – kein Prompt im curl-Fluss.
- Fehlt ein einzelner Key in einer bereits bestehenden Config (z. B. nach einem basher-Update, das
  einen neuen Key einführt), wird beim Laden nur dieser eine Key mit Default aufgefüllt – additiv,
  kein Config-Versionsfeld nötig.
- `INSTALL_MODE` ist bewusst kein Teil des interaktiven Walkthroughs, sondern wird primär von
  `install.sh` gesetzt. Über `basher config set INSTALL_MODE <wert>` technisch überschreibbar –
  als Debug-Hintertür, nicht als beworbener Workflow.

### 2.4 Config-Subcommands
- `basher config` – interaktiver Walkthrough (nur Voll-Modus, s. 1.5 `require_full_install`), zeigt
  vor jeder Abfrage eine kurze Erklärung des jeweiligen Keys (`basher_config_hint` in
  `lib/config.sh`)
- `basher config get <key>`
- `basher config set <key> <value>`
- `basher config path` – gibt Pfad zur Config-Datei aus
- `basher config edit` – öffnet Config-Datei im Editor

---

## 3. Script-Repo

### 3.1 Ein aktives Script-Repo
Es gibt genau **ein** konfiguriertes Script-Repo (`REPO_PATH`), in das `new`/`edit` schreiben.
Kategorisierung erfolgt über die Ordnerstruktur innerhalb von `REPO_PATH`.

Tmp-Scripts (`basher tmp`) landen **nie** in diesem Repo – sie sind rein transient (siehe 5.1) und
tauchen daher auch nicht im Manifest auf.

### 3.2 Privat vs. öffentlich
- **Öffentlich**: `git clone`/`curl` funktionieren anonym.
- **Privat**: lokal via SSH-Key/HTTPS-Credentials wie gewohnt. Für den curl-Minimal-Modus gegen
  ein privates Repo: `GITHUB_TOKEN` als Env-Var, wird als `Authorization`-Header an `curl`
  durchgereicht. Ohne Token ist ein privates Repo im Minimal-Modus nicht erreichbar.

### 3.3 Repo wechseln: `basher repo set <pfad-oder-url> [--ssh|--https]`
Erkennt automatisch, ob die Eingabe ein lokaler Pfad oder eine Git-URL ist
(`basher_looks_like_git_url` in `lib/repo.sh`):

- **Lokaler Pfad**: setzt nur `REPO_PATH`, wie zuvor.
- **Git-URL** (`https://…`, `git@…`, `ssh://…`): fragt – sofern nicht per `--ssh`/`--https`
  vorgegeben – interaktiv, ob SSH oder HTTPS für Push/Pull genutzt werden soll (Default fett
  hervorgehoben statt in Textform ausformuliert, s. 1.7), und konvertiert die URL bei Bedarf
  zwischen beiden Formaten (`basher_git_url_to_ssh`/`_to_https`). Fragt danach nach dem
  gewünschten Zielpfad (Default: `~/.local/share/basher/scripts`). Ist der Zielpfad leer/nicht
  vorhanden, wird die URL dorthin geklont; ist dort bereits ein Git-Repo vorhanden, wird nur der
  `origin`-Remote aktualisiert. Existiert am Zielpfad bereits etwas anderes (nicht-leer, kein
  Git-Repo), bricht basher ab statt etwas zu überschreiben. `REPO_URL` wird erst nach
  erfolgreichem Klonen/Verknüpfen gesetzt – bei einem Fehler bleibt der alte Wert unangetastet.

Dieselbe Logik (`basher_repo_set_smart`) greift auch im Config-Walkthrough (s. 2.4): wird bei der
`REPO_PATH`-Abfrage eine URL statt eines Pfads eingegeben, läuft automatisch derselbe Ablauf.

### 3.4 Ad-hoc-Repo in der curl-Variante
Mit `--repo <owner/repo>` (oder `BASHER_REPO`-Env-Var) referenziert `basher run` bei jedem
einzelnen Aufruf ein beliebiges öffentliches GitHub-Repo, unabhängig von der lokalen Konfiguration
(`lib/remote.sh`, `basher_remote_fetch`):

```
curl -fsSL <raw-url-zu-basher-minimal> | bash -s -- run tools/backup.sh --repo someone/their-scripts
```

Der Zugriff erfolgt über `raw.githubusercontent.com`, ohne GitHub-API und damit ohne
Rate-Limit-Risiko. Da der Default-Branch dabei nicht bekannt ist, probiert basher `main` und
`master` durch (`BASHER_REMOTE_BRANCHES` in `lib/remote.sh`).

`list`/`run` funktionieren nur, wenn im Root des referenzierten Repos ein `manifest.idx` liegt
(s. 3.6) – das ist die einzige Voraussetzung, die ein Repo zu einem gültigen basher-Script-Store
macht. Fehlt die Datei (in beiden probierten Branches), bricht `require_manifest` (s. 1.5) mit
einer klaren Meldung ab statt mit einem rohen Verbindungsfehler.

### 3.5 Repo synchronisieren: `auto`- vs. `pro`-Modus
Gesteuert über `SYNC_MODE` (Default `auto`, s. 2.2) – zwei bewusst unterschiedliche Philosophien:

**`auto` (Default)**:
- `basher repo sync` macht `git fetch`, dann `git pull --rebase` (lokale Commits werden auf den
  aktuellen Remote-Stand umgesetzt), danach `git push`.
- Ist `AUTO_COMMIT=true` **und** `SYNC_MODE=auto`, führt bereits `basher new`/`edit` **vor** dem
  Öffnen des Editors automatisch ein `git pull --rebase` aus. Nach dem Schließen des Editors:
  Commit + `repo sync` (Push) automatisch.
- Fehlt ein Upstream-Tracking-Branch (z. B. frisches Repo, Remote gerade erst hinzugefügt), wird
  der Pull übersprungen statt fälschlich als Konflikt behandelt zu werden.
- Tritt beim Rebase ein echter Inhaltskonflikt auf, bricht basher den Rebase sauber ab
  (`git rebase --abort`, kein halb-gerebaster Zustand) und gibt eine klare Meldung aus: manuell in
  `REPO_PATH` prüfen (`git status`), oder `SYNC_MODE=pro` setzen, um Automatik zu deaktivieren.

**`pro`**:
- `basher repo sync` verändert nichts automatisch, sondern zeigt nur den Status (Commits
  voraus/hinter Remote).
- Kein automatischer Pre-Pull vor `new`/`edit`, auch wenn `AUTO_COMMIT=true` – dann committet
  basher nur lokal, alles Weitere macht der Nutzer selbst per `git`.

Umschalten jederzeit per `basher config set SYNC_MODE pro` (bzw. `auto`).

### 3.6 Manifest-Format
Pro Repo eine flache Datei `manifest.idx` im Repo-Root, ein Eintrag pro Zeile, Pipe-getrennt
(kein JSON, kein `jq` im Minimal-Modus nötig). Erste Zeile ein Versions-Kommentar (Parser
ignoriert Zeilen, die mit `#` beginnen):

```
# basher-manifest v1
kategorie/pfad/zum/script.sh|Kurzbeschreibung
helper/user/cleanup.sh|Räumt alte Nutzerverzeichnisse auf
```

Wird bei jedem `new`/`edit`/`repo scan` automatisch aktualisiert (`lib/manifest.sh`). Tmp-Scripts
tauchen nicht im Manifest auf.

### 3.7 Manifest aus bestehender Struktur erzeugen: `basher repo scan [pfad]`
Für bereits vorhandene, per Ordnerstruktur kategorisierte Script-Sammlungen ohne `manifest.idx`:
durchsucht das Repo (Default: `REPO_PATH`) rekursiv nach `*.sh`-Dateien und gleicht das Manifest
ab (`basher_manifest_scan` in `lib/manifest.sh`):

- neue Scripts werden mit leerer Beschreibung ergänzt
- Einträge zu nicht mehr existierenden Dateien werden entfernt
- bestehende Beschreibungen bleiben unangetastet

Idempotent – mehrfaches Ausführen ohne Änderungen am Dateisystem verändert das Manifest nicht.

---

## 4. Secrets

### 4.1 Default: Plain-Env-Datei
`SECRETS_FILE` (Default `~/.config/basher/secrets.env`), außerhalb jedes Git-Repos. `chmod 600`
bei Erstellung; jeder Zugriff (`get`, `list`, `edit`, das Laden vor Script-Ausführung) prüft die
Dateirechte und korrigiert automatisch bei Abweichung von 600.

### 4.2 Optionales GPG-Toggle
`basher secrets encrypt` verschlüsselt die bestehende Plain-Datei einmalig symmetrisch (`gpg -c`,
Passphrase statt Keypair – kein Schlüsselmanagement nötig) nach `secrets.env.gpg`, entfernt den
Klartext (`shred -u`, Fallback `rm -f`) und setzt `SECRETS_MODE=gpg`. `basher secrets decrypt`
kehrt den Vorgang um. Laden erfolgt via Process-Substitution (`source <(gpg -d ...)`), die Datei
landet dabei nie unverschlüsselt auf der Platte. Passphrase-Caching übernimmt `gpg-agent`.
`basher secrets edit` im GPG-Modus entschlüsselt in eine temporäre Datei unter `/dev/shm` (falls
verfügbar), öffnet den Editor, verschlüsselt danach zurück und entfernt die temporäre Datei sicher.

### 4.3 Fallback-Verhalten
`require_gpg` (s. 1.5) prüft `command -v gpg`. Fehlt `gpg` (typisch auf schlanken
Headless-Servern) und ist `SECRETS_MODE=gpg` aktiv, gibt basher beim Laden eine klare Warnung aus
und führt das Script ohne die Secrets aus, statt abzubrechen.

### 4.4 Subcommands
`basher secrets set <KEY> <WERT>` · `get <KEY>` · `list` (nur Key-Namen, keine Werte) · `edit` ·
`encrypt` · `decrypt`.

### 4.5 Integration mit Script-Ausführung
`basher_secrets_load` (`lib/secrets.sh`) exportiert alle Secrets als Umgebungsvariablen in die
aktuelle Shell, bevor ein Script gestartet wird – eingebunden in `basher run` (lokal und remote)
sowie in `basher tmp`.

---

## 5. Workflows im Detail

### 5.1 `basher tmp`
Erstellt `bashertmp-<timestamp>-<pid>.sh` in `TMP_DIR`, Shebang + `chmod +x`, öffnet Editor (1.3).
Ist die Datei nach dem Editor leer (nur Shebang/Leerzeilen), wird sie ohne Rückfrage verworfen.

`TMP_DIR` liegt in `${TMPDIR:-/tmp}/basher` als Sicherheitsnetz für den Fall eines Absturzes –
verlassen kann man sich darauf aber nicht: je nach Distro wird `/tmp` erst beim Reboot geleert
(tmpfs) oder erst nach mehreren Tagen (`systemd-tmpfiles-clean.timer`). Die eigentliche Löschung
übernimmt basher deshalb aktiv über folgenden Flow:

```
Editor schließen
   │
   ▼
"Ausführen? [j/N]"
   ├─ Nein ──────────────► Script löschen, Ende
   └─ Ja
       │
       ▼
   (#1) Secrets laden, Script ausführen
       │
       ▼
   "Nochmal ausführen? [j/N]"
       ├─ Nein ──────────► Script löschen, Ende
       └─ Ja ────────────► zurück zu (#1)
```

Tmp-Scripts landen nie im Script-Repo (s. 3.1). Wer ein Tmp-Script dauerhaft behalten will, nutzt
bewusst `basher new`.

### 5.2 `basher new [name] [--category <pfad>]`
Fehlt `name`, wird abgefragt. `--category` erzeugt/nutzt Unterordner innerhalb von `REPO_PATH`.
Ist `AUTO_COMMIT=true` und `SYNC_MODE=auto`: erst `git pull --rebase` (s. 3.5), **dann** Datei
anlegen, Shebang, `chmod +x`, Manifest-Eintrag, Editor öffnen. Nach dem Schließen: lokaler Commit
+ automatischer `repo sync` (Push).

### 5.3 `basher edit [name-or-path]`
Löst die Eingabe über `basher_manifest_resolve` (`lib/manifest.sh`) auf – per exaktem Pfad oder
per Basename, mit oder ohne `.sh`-Endung. Gibt es mehrere Treffer für denselben Namen (z. B.
gleichnamige Scripts in unterschiedlichen Kategorien), bietet `basher_manifest_disambiguate` eine
Auswahl an: `fzf` im Voll-Modus (mit Preview), eine nummerierte Liste per `read` sonst – damit
auch im Minimal-/curl-Fall nutzbar. Ohne jedes Argument im Voll-Modus: direkter fzf-Picker über
das gesamte Script-Repo. Öffnet das Script im Editor, zeigt danach die aktuelle Kurzbeschreibung
als Default und aktualisiert sie bei Bedarf im Manifest. Gleiches `AUTO_COMMIT`/`SYNC_MODE`-
Verhalten wie `new` (s. 5.2).

### 5.4 `basher list` / `basher menu`
- `list`: reine Textausgabe (Minimal-tauglich), gruppiert nach dem tatsächlichen Verzeichnis jedes
  Eintrags (nicht nur der Top-Level-Kategorie).
- `menu` bzw. `basher` ohne Argumente (nur Voll-Modus): interaktives fzf-Menü mit Preview-Pane
  (Scriptinhalt, `bat` falls vorhanden sonst `cat`). Keybindings:
  - `Enter` → Script direkt **ausführen** (ruft intern denselben Code wie `basher run`)
  - `Ctrl-E` → Script stattdessen zum **Bearbeiten** öffnen (ruft intern `basher edit`)

  `cmd_menu` ruft zuerst `require_full_install`, dann `require_fzf` auf (s. 1.5) – im Minimal-Modus
  bzw. bei fehlendem `fzf` erscheint eine handlungsanweisende Meldung statt eines rohen
  `command not found`-Fehlers.

### 5.5 `basher run <name-or-path> [--repo <owner/repo>] [-- Argumente]`
Führt ein Script aus, ohne es zu öffnen; lädt vorher die Secrets (s. 4.5). Ohne `--repo` wird das
konfigurierte `REPO_PATH` genutzt. Mit `--repo` (oder `BASHER_REPO`-Env) wird stattdessen ad-hoc
ein beliebiges öffentliches GitHub-Repo angesprochen (s. 3.4): lädt dessen `manifest.idx`, löst
den Pfad auf (inkl. Mehrdeutigkeits-Auswahl, s. 5.3), lädt die Rohdatei in eine temporäre Datei
und führt sie per `bash <tmp-datei>` aus – ein `chmod +x` ist dafür nicht nötig. Alles nach
`--` wird unverändert an das ausgeführte Script durchgereicht.

### 5.6 `basher config …`
Siehe 2.4.

### 5.7 `basher repo …`
- `basher repo scan [pfad]` – siehe 3.7 (Default: `REPO_PATH`)
- `basher repo set <pfad-oder-url> [--ssh|--https]` – siehe 3.3
- `basher repo sync` – siehe 3.5 (Verhalten abhängig von `SYNC_MODE`)

### 5.8 `basher secrets …`
Siehe 4.4.

### 5.9 `install.sh` / `uninstall.sh`
- `install.sh [--minimal|--full]`: installiert per Default die Vollversion (`--full` als
  expliziter Alias); `--minimal` für die schlanke Variante. Installiert einen Wrapper nach
  `~/.local/bin/basher`, der per `exec` auf den absoluten Pfad des Repos zeigt (kein `sudo`, kein
  Symlink). Voll-Modus prüft/installiert `fzf` über den erkannten Paketmanager
  (pacman/apt/dnf/brew), warnt statt abzubrechen, falls das nicht klappt, und startet danach direkt
  den Config-Walkthrough (s. 2.3). Setzt `INSTALL_MODE` in der Config über `basher config set`
  (keine doppelte Logik).
- `uninstall.sh`: entfernt nur den Wrapper (reine Tool-Infrastruktur, keine Rückfrage nötig).
  Fragt getrennt und explizit nach, ob Config bzw. Secrets-Datei (Pfad abhängig vom aktuellen
  `SECRETS_MODE`, s. 4.1/4.2) ebenfalls gelöscht werden sollen – Default ist in beiden Fällen
  **Behalten**. Das Script-Repo wird nie angefasst.

### 5.10 `basher version`
Diagnose-Ausgabe: Versionsstring, `INSTALL_MODE`, `REPO_PATH`, Pfad der Config-Datei.

### 5.11 `basher help` / `-h` / `--help`
Zweistufige Hilfe direkt im Terminal, keine externe `man`-Abhängigkeit (bewusste Entscheidung
gegen eine Man-Page, s. 8): `-h`/`--help` (`cmd_help`) zeigt eine kompakte Befehlsübersicht, das
eigenständige `help` (`cmd_help_full`) eine ausführlichere Fassung mit Beispielen, Config- und
Dateien-Überblick. `bin/basher` (und das Minimal-Bundle-Template) behandeln alle drei Formen als
Sonderfall vor der generischen `cmd_$1`-Auflösung, da `--help` sonst keinen gültigen
Funktionsnamen ergäbe.

---

## 6. Subcommand-Referenztabelle

| Command | Zweck | Minimal-Modus | Voll-Modus |
|---|---|---|---|
| `basher tmp` | temporäres Script erstellen & ausführen | ✅ | ✅ |
| `basher new` | neues benanntes Script erstellen | ✅ | ✅ |
| `basher edit [x]` | bestehendes Script bearbeiten | ✅ (mit Namen + Auswahlliste bei Mehrdeutigkeit) | ✅ (+ fzf-Picker) |
| `basher list` | Textliste aller Scripts | ✅ | ✅ |
| `basher menu` / `basher` | interaktives fzf-Menü (Enter=ausführen, Ctrl-E=bearbeiten) | ❌ | ✅ |
| `basher run <x>` | Script ausführen ohne Editor, lokal oder `--repo owner/repo` | ✅ | ✅ |
| `basher config …` | Config lesen/setzen | ✅ (get/set/path/edit) | ✅ (+ interaktiver Walkthrough) |
| `basher repo …` | `scan`, `set`, `sync` | ✅ | ✅ |
| `basher secrets …` | `set`/`get`/`list`/`edit`/`encrypt`/`decrypt` | ✅ | ✅ |
| `basher version` | Diagnose-Ausgabe | ✅ | ✅ |
| `basher help` / `-h` / `--help` | Befehlsübersicht | ✅ | ✅ |
| `install.sh` | Installation | ✅ | ✅ |
| `uninstall.sh` | Deinstallation | ✅ | ✅ |

---

## 7. Repo-Struktur

```
basher/
├── README.md
├── install.sh
├── uninstall.sh
├── build-minimal.sh          # generiert minimal/basher-minimal.sh aus lib/*.sh
├── docs/
│   └── architecture.md        # dieses Dokument
├── bin/
│   └── basher                 # Haupt-Entrypoint, nur Dispatcher (s. 1.4)
├── lib/
│   ├── config.sh               # Config laden/lesen/schreiben/validieren (s. 2)
│   ├── checks.sh                # Guard-Funktionen + basher_die (s. 1.5/1.6)
│   ├── core.sh                  # Editor-Fallback-Kette (s. 1.3)
│   ├── repo.sh                  # Git-Interaktion: pull/push/commit/sync (s. 3.5)
│   ├── manifest.sh              # manifest.idx lesen/schreiben/scannen/auflösen (s. 3.6/3.7)
│   ├── remote.sh                # Ad-hoc-Zugriff auf fremde GitHub-Repos (s. 3.4)
│   ├── secrets.sh                # Secrets laden/bearbeiten/migrieren (s. 4)
│   └── commands/                 # ein File pro Subcommand, je eine cmd_<name>()-Funktion (s. 1.4)
│       ├── config.sh
│       ├── edit.sh
│       ├── help.sh
│       ├── list.sh
│       ├── menu.sh
│       ├── new.sh
│       ├── repo.sh
│       ├── run.sh
│       ├── secrets.sh
│       ├── tmp.sh
│       └── version.sh
└── minimal/
    └── basher-minimal.sh      # generiertes, self-contained Single-File-Bundle für curl-Pipe
                                 # (NICHT von Hand bearbeiten, s. build-minimal.sh)
```

---

## 8. Wichtige Detailentscheidungen

**`INSTALL_MODE`**: primär von `install.sh` gesetzt und nicht Teil des interaktiven
`basher config`-Walkthroughs (s. 2.3), aber via `basher config set INSTALL_MODE <wert>` technisch
überschreibbar – bewusst als Debug-Hintertür, nicht als beworbener Workflow. Keine zusätzliche
Guard-Logik, die das verhindert.

**Mehrdeutige Skriptnamen**: `edit`/`run` bieten bei mehreren Treffern für denselben Namen eine
Auswahl an statt abzubrechen (s. 5.3) – im Voll-Modus per `fzf`, im Minimal-Modus per nummerierter
Liste, damit auch der curl-Fall abgedeckt ist.

**`basher_die` aus Command-Substitutions heraus**: `basher_die` beendet zuverlässig den gesamten
Prozess unabhängig davon, aus welcher Verschachtelungstiefe (auch innerhalb von `$(...)`) es
aufgerufen wird (s. 1.6) – relevant für praktisch jede Fehlermeldung im Projekt.

**Config-Walkthrough beim Erstaufruf**: lief ursprünglich gar nicht automatisch, obwohl so
dokumentiert – `basher_config_load` legt die Config immer nur still mit Defaults an. Gefixt, indem
`install.sh --full` den Walkthrough direkt anstößt (s. 2.3), statt ihn vom zufälligen ersten
`basher`-Aufruf abhängig zu machen.

**`REPO_URL` war totes Config-Feld**: ursprünglich als Schema-Eintrag vorgesehen, aber nirgends
tatsächlich für Push/Pull genutzt (Git nutzt seinen eigenen, manuell konfigurierten
`origin`-Remote). Gefixt durch `basher_repo_set_smart` (s. 3.3): erkennt URLs automatisch, fragt
SSH/HTTPS ab, klont/verknüpft entsprechend und setzt `REPO_URL` als tatsächlich genutzten Wert.

**`install.sh` Default auf Vollinstallation umgestellt**: ursprünglich fragte `install.sh` ohne
Flag interaktiv Minimal/Voll ab. Da das Klonen des Repos bereits eine bewusste Entscheidung ist,
ist „Vollversion" der sinnvollere Default – `--minimal` für die schlanke Variante bleibt explizit
wählbar, die Auswahlfrage entfällt.

**Man-Page verworfen zugunsten von `basher help`**: eine erste Version installierte eine echte
`man`-Page nach `~/.local/share/man`. In der Praxis von `man-db`/`MANPATH`-Eigenheiten des
jeweiligen Systems abhängig und dadurch nicht zuverlässig auffindbar. Ersetzt durch die
zweistufige `-h`/`--help`/`help`-Lösung direkt in basher selbst (s. 5.11) – keine externe
Abhängigkeit, funktioniert identisch überall.

**ASCII-Banner im Config-Walkthrough**: ersetzt die vorherige reine Textzeile
(„basher Config-Walkthrough - Enter übernimmt...“) sowie die zusätzliche Erklärung in `install.sh`
davor – der Banner (`basher_config_walkthrough` in `lib/commands/config.sh`) macht auf einen Blick
klar, dass jetzt die Konfiguration folgt, ohne zusätzlichen erklärenden Text.
