# basher – Architektur- & Funktionsplan (Entwurf v0.1)

Referenznummern zum Kommentieren. Alles hier ist Vorschlag, keine Festlegung.

---

## 1. Grundarchitektur

### 1.1 Trennung: Tool-Repo vs. Script-Store(s)
`basher` (das Tool) und die eigentlichen `.sh`-Scripts liegen in getrennten Repos/Verzeichnissen.
Das basher-Repo enthält nur Code des Managers (install/uninstall, bin/, lib/). Wo Nutzer-Scripts
gespeichert werden, ist reine Konfigurationssache (siehe 3).

### 1.2 Installationsmodi
- **Minimal**: einzelnes, self-contained Bash-Script, keine externen Pakete außer `curl`/`bash`
  selbst. Läuft per `curl -fsSL <raw-url> | bash -s -- <command>` ohne vorherige Installation.
- **Voll**: lokaler Clone, modulare `lib/*.sh`, nutzt `fzf` für interaktives Menü, optional weitere
  Komfort-Tools (z. B. `bat` für Preview, falls vorhanden).
- `install.sh` fragt interaktiv Minimal/Voll ab, oder nimmt Flags: `install.sh --minimal|--full`.

### 1.3 Editor & Ausführung
Fallback-Kette statt hartkodiertem `nvim`: `$EDITOR` → `nvim` → `vim` → `vi`.
Vor Ausführung eines frisch bearbeiteten Scripts: `bash -n <script>` als Syntax-Check, danach
Rückfrage ob ausgeführt werden soll (kein automatisches Blind-Execute).

### 1.4 Erweiterbarkeit: Command-Dispatcher statt if/elif-Kette
Damit neue Subcommands später ohne Eingriff in bestehenden Code hinzukommen, bekommt jeder
Subcommand eine eigene Funktion `cmd_<name>()` in einer eigenen Datei unter `lib/commands/`
(Voll-Modus) bzw. im gleichen Namensschema innerhalb der Single-File-Variante (Minimal-Modus,
s. 1.2/7). `bin/basher` selbst ist nur ein dünner Dispatcher:

```bash
cmd="cmd_${1:-menu}"; shift || true
if declare -f "$cmd" > /dev/null; then "$cmd" "$@"; else echo "Unbekannter Befehl: $1" >&2; exit 1; fi
```

Ein neuer Befehl später bedeutet: neue Datei in `lib/commands/`, Funktion `cmd_foo()` schreiben,
fertig – kein Anfassen von `bin/basher`. Minimal- und Voll-Variante nutzen bewusst dasselbe
Namensschema (`cmd_*`), auch wenn der Minimal-Code physisch in einer Datei gebündelt bleibt –
das hält beide Codepfade gedanklich synchron, falls ein Befehl in beiden Varianten existieren soll.

### 1.5 Guard-Funktionen statt verstreuter Fehlerbehandlung
Statt jede Fehlerprüfung einzeln im jeweiligen Befehl zu wiederholen, gibt es zentrale
Guard-Funktionen (`lib/checks.sh`), die Vorbedingungen prüfen und bei Nichterfüllung eine klare,
handlungsanweisende Meldung ausgeben statt einfach zu crashen:

- `require_full_install` – bricht mit Meldung ab, falls `INSTALL_MODE != full` (s. 2.2, 5.4)
- `require_fzf` – bricht mit Meldung ab, falls `fzf` trotz Vollinstallation fehlt (z. B. manuell
  deinstalliert)
- `require_manifest <repo-pfad>` – bricht mit Meldung ab, falls kein `manifest.idx` im Root
  gefunden wird (s. 3.4/3.6)
- `require_gpg` – s. 4.3, gleiches Prinzip

Jeder neue Befehl ruft am Anfang die passenden Guards auf statt eigene Ad-hoc-Prüfungen zu bauen –
das ist der zweite Baustein für Erweiterbarkeit neben 1.4: neue Subcommands bekommen
Fehlerbehandlung „geschenkt“, ohne sie neu zu erfinden.

---

## 2. Konfiguration

### 2.1 Speicherort & Format
`~/.config/basher/config` – einfache `KEY="value"`-Datei, direkt in Bash sourcebar (kein
YAML/JSON-Parser nötig → bleibt Minimal-Modus-kompatibel).

### 2.2 Config-Schema (Vorschlag)

| Key | Beschreibung | Default |
|---|---|---|
| `INSTALL_MODE` | `minimal` oder `full` – von `install.sh` gesetzt, zur Laufzeit von Guards geprüft (s. 1.5) | wird bei Installation verpflichtend gesetzt |
| `REPO_PATH` | Lokaler Pfad zum geklonten Script-Repo | `~/.local/share/basher/scripts` |
| `REPO_URL` | Remote-URL des Script-Repos (für `repo sync`) | leer, wird bei Bedarf gesetzt |
| `EDITOR_CMD` | Override für Editor | leer (→ Fallback-Kette 1.3) |
| `TMP_DIR` | Ablageort temporärer Scripts (Sicherheitsnetz, s. 5.1) | `${TMPDIR:-/tmp}/basher` |
| `AUTO_SYNTAX_CHECK` | `bash -n` vor Ausführung | `true` |
| `AUTO_COMMIT` | nach `new`/`edit` lokal automatisch committen | `false` (wird bei `install.sh` abgefragt, s. 5.8) |
| `SYNC_MODE` | Verhalten von `repo sync`: `auto` oder `pro` (s. 3.5) | `auto` |
| `SECRETS_MODE` | `plain` oder `gpg` | `plain` |
| `SECRETS_FILE` | Pfad zur Secrets-Datei | `~/.config/basher/secrets.env` |

### 2.3 Erststart-Verhalten
- Voll-Modus: fehlt die Config, interaktive Abfrage der wichtigsten Werte (mit Enter = Default).
- Minimal-Modus: fehlt die Config, wird sie stumm mit Defaults angelegt (kein Prompt möglich/nötig
  auf einem Headless-Server im curl-Fluss).
- Fehlt ein einzelner Key in einer bereits bestehenden Config (z. B. nach einem basher-Update, das
  einen neuen Key wie `SYNC_MODE` einführt), wird beim Laden nur dieser eine Key mit Default
  aufgefüllt – kein Config-Versionsfeld nötig, da neue Keys additiv sind und alte Configs nicht
  brechen.

### 2.4 Config-Subcommands
- `basher config` – interaktiver Walkthrough (nur Voll-Modus)
- `basher config get <key>`
- `basher config set <key> <value>`
- `basher config path` – gibt Pfad zur Config-Datei aus
- `basher config edit` – öffnet Config-Datei im Editor

---

## 3. Script-Repo (vereinfacht)

### 3.1 Ein aktives Script-Repo, kein Multi-Repo-Management
Wir verzichten vorerst auf eine Multi-Repo-Registry. Es gibt genau **ein** konfiguriertes
Script-Repo (`REPO_PATH`/`REPO_URL`), in das `new`/`edit` schreiben. Das deckt den Hauptfall ab;
die curl-Variante bleibt trotzdem flexibel (siehe 3.4).

Tmp-Scripts (`basher tmp`) landen **nie** in diesem Repo – sie sind rein transient (siehe 5.1)
und tauchen daher auch nicht im Manifest auf.

### 3.2 Privat vs. öffentlich
- **Öffentlich**: `git clone`/`curl` funktionieren anonym.
- **Privat**: lokal via SSH-Key/HTTPS-Credentials wie gewohnt. Für den curl-Minimal-Modus gegen
  ein privates Repo: `GITHUB_TOKEN` als Env-Var, wird als `Authorization`-Header an `curl`
  durchgereicht. Ohne Token ist ein privates Repo im Minimal-Modus schlicht nicht erreichbar.

### 3.3 Repo wechseln
`basher repo set <url>` – setzt `REPO_URL`, klont (falls noch nicht vorhanden) nach `REPO_PATH`.

### 3.4 Ad-hoc-Repo in der curl-Variante
Kein Registrierungszwang: mit `--repo <owner/repo>` (oder `BASHER_REPO`-Env-Var) kannst du bei
jedem einzelnen curl-Aufruf ein beliebiges öffentliches GitHub-Repo referenzieren, unabhängig von
deiner lokalen Konfiguration:

```
curl -fsSL <raw-url-zu-basher-minimal> | bash -s -- --repo someone/their-scripts list
curl -fsSL <raw-url-zu-basher-minimal> | bash -s -- --repo someone/their-scripts run tools/backup.sh
```

Damit bleibt „beliebiges öffentliches Repo lesen/ausführen“ möglich, ohne die Komplexität einer
dauerhaften Multi-Repo-Verwaltung.

**Ja, korrekt:** `list`/`run` funktionieren nur, wenn im Root des referenzierten Repos ein
`manifest.idx` liegt (s. 3.6) – das ist die einzige Voraussetzung, die ein Repo zu einem gültigen
basher-Script-Store macht. Fehlt die Datei, ist das kein Crash, sondern ein klarer Fehler über die
Guard-Funktion `require_manifest` (s. 1.5): „Kein manifest.idx im Root von `owner/repo` gefunden –
das scheint kein gültiger basher-Script-Store zu sein.“

### 3.5 Repo synchronisieren: `auto`- vs. `pro`-Modus
Gesteuert über `SYNC_MODE` (Default `auto`, s. 2.2) – zwei bewusst unterschiedliche Philosophien:

**`auto` (Default, „Leicht-Modus“)** – für den Fall „ich vergesse meistens zu pullen, bevor ich
Änderungen mache“:
- `basher repo sync` macht `git fetch`, dann `git pull --rebase` (lokale Commits werden auf den
  aktuellen Remote-Stand umgesetzt), danach `git push`.
- Zusätzlich: Ist `AUTO_COMMIT=true` **und** `SYNC_MODE=auto`, führt bereits `basher new`/`edit`
  **vor** dem Öffnen des Editors automatisch ein `git pull --rebase` aus – genau das behebt das
  „vergesse zu pullen, bevor ich Änderungen mache“-Problem an der Wurzel, nicht erst beim
  nachträglichen `sync`. Nach dem Schließen des Editors: Commit + `repo sync` (push) automatisch.
- Tritt beim Rebase ein **echter Inhaltskonflikt** auf (unvermeidbar, wenn zwei Seiten dieselbe
  Zeile geändert haben), bricht basher den Rebase sauber ab (`git rebase --abort`, kein
  halb-gerebaster Zustand) und gibt eine klare Meldung: „Konflikt beim Sync – bitte manuell in
  `REPO_PATH` prüfen (`git status`), oder `SYNC_MODE=pro` setzen, um Automatik zu deaktivieren.“
  Das ist der einzige Fall, in dem Automatik an ihre Grenze stößt – lässt sich nicht wegdesignen.

**`pro`** – für Nutzer, die ihr Repo bewusst selbst managen wollen:
- `basher repo sync` verändert **nichts** automatisch, sondern zeigt nur den Status
  („3 Commits hinter Remote, 2 eigene Commits voraus – bitte manuell `pull`/`push`“).
- Kein automatischer Pre-Pull vor `new`/`edit`, auch wenn `AUTO_COMMIT=true` – dann committet
  basher nur lokal, alles Weitere macht der Nutzer selbst per `git`.

Umschalten jederzeit per `basher config set SYNC_MODE pro` (bzw. `auto`).

### 3.6 Manifest-Format
Pro Repo eine flache Datei `manifest.idx` im Repo-Root, ein Eintrag pro Zeile, Pipe-getrennt
(bewusst kein JSON → kein `jq` nötig im Minimal-Modus). Erste Zeile optional ein Versions-Kommentar
(Parser ignoriert Zeilen, die mit `#` beginnen) – kostet nichts, gibt uns aber Raum, das Format
später zu erweitern (z. B. um ein drittes Feld für Tags), ohne alte Manifeste zu brechen:

```
# basher-manifest v1
kategorie/pfad/zum/script.sh|Kurzbeschreibung
helper/user/cleanup.sh|Räumt alte Nutzerverzeichnisse auf
mount/fstab/add-entry.sh|Fügt fstab-Eintrag hinzu
```

Wird bei jedem `new`/`edit`/`remove` automatisch aktualisiert. Tmp-Scripts (siehe 1.3, 5.1)
tauchen **nicht** im Manifest auf.

---

## 4. Secrets

### 4.1 Default: Plain-Env-Datei
`SECRETS_FILE` (default `~/.config/basher/secrets.env`), außerhalb jedes Git-Repos.
Automatisch `chmod 600` bei Erstellung, Rechte-Check bei jedem Start mit Warnung bei Abweichung.

### 4.2 Optionales GPG-Toggle
`basher config set SECRETS_MODE gpg` verschlüsselt bestehende Datei einmalig symmetrisch
(`gpg -c`, Passphrase statt Keypair – kein Schlüsselmanagement nötig). Laden via
Process-Substitution (`source <(gpg -d secrets.env.gpg)`), Datei landet nie unverschlüsselt auf
Platte. Passphrase-Caching übernimmt `gpg-agent`.

### 4.3 Fallback-Verhalten
Zur Laufzeit `command -v gpg` prüfen. Fehlt `gpg` (typisch auf schlanken Headless-Servern), fällt
basher automatisch auf `plain` zurück und gibt eine klare Meldung aus – kein harter Fehler.

---

## 5. Workflows im Detail

### 5.1 `basher tmp`
Erstellt `bashertmp-<timestamp>.sh` in `TMP_DIR`, Shebang + `chmod +x`, öffnet Editor (1.3).

**Zum Thema „räumt sich das von selbst auf“:** Verlass dich nicht auf automatisches
OS-Verhalten von `/tmp`. Je nach Distro ist `/tmp` entweder tmpfs (wird erst beim **Reboot**
geleert, nicht am „Session-Ende“) oder unterliegt `systemd-tmpfiles-clean.timer`, der Dateien oft
erst nach mehreren Tagen löscht. Das ist nicht deterministisch genug. Deshalb liegt `TMP_DIR`
zwar in `/tmp/basher` als **Sicherheitsnetz** (falls basher mal hart abstürzt, räumt das OS
irgendwann nach), die eigentliche Löschung übernimmt basher aber **aktiv** über folgenden Flow –
genau wie skizziert:

```
Editor schließen
   │
   ▼
"Ausführen? [j/N]"
   ├─ Nein ──────────────► Script löschen, Ende
   └─ Ja
       │
       ▼
   (#1) Script ausführen
       │
       ▼
   "Nochmal ausführen? [j/N]"
       ├─ Nein ──────────► Script löschen, Ende
       └─ Ja ────────────► zurück zu (#1)
```

Kein „Behalten/In Kategorie verschieben“ mehr (passt zu 3.1: Tmp-Scripts landen nie im
Script-Repo). Wer ein Tmp-Script dauerhaft behalten will, nutzt bewusst `basher new` – kein
Automatismus, der Tmp- und Repo-Welt vermischt.

### 5.2 `basher new [name] [--category <pfad>]`
Fehlt `name`, wird abgefragt. `--category` erzeugt/nutzt Unterordner (Kategorisierung via
Dateisystem) innerhalb von `REPO_PATH`. Ist `AUTO_COMMIT=true` und `SYNC_MODE=auto`: erst
`git pull --rebase` (s. 3.5), **dann** Datei anlegen, Shebang, `chmod +x`, Manifest-Eintrag,
Editor öffnen. Nach dem Schließen: lokaler Commit + automatischer `repo sync` (Push).

### 5.3 `basher edit <name-or-path>`
Ohne Argument im Voll-Modus: fzf-Picker über das konfigurierte Script-Repo (`REPO_PATH`). Öffnet
Script im Editor, aktualisiert bei Bedarf die Kurzbeschreibung im Manifest.

### 5.4 `basher list` / `basher menu`
- `list`: reine Textausgabe (Minimal-tauglich), gruppiert nach Kategorie.
- `menu` bzw. `basher` ohne Argumente (nur Voll-Modus): interaktives fzf-Menü mit Preview-Pane
  (Scriptinhalt, `bat` falls vorhanden sonst `cat`), gruppiert nach Kategorie. Keybindings:
  - `Enter` → Script direkt **ausführen** (Hauptaktion, ruft intern denselben Code wie `basher run`)
  - `Ctrl-E` → Script stattdessen zum **Bearbeiten** öffnen (ruft intern `basher edit`)

  So deckt das Menü beide Fälle ab: schnelles Ausführen beim Durchstöbern, und gezieltes
  Ansprechen eines bekannten Scripts weiterhin direkt über `basher run <name>` (z. B. aus eigenen
  Aliasen/anderen Scripts, wo kein interaktives Menü gewünscht ist).

  **Zugriffsschutz statt Crash:** `cmd_menu()` ruft als Erstes `require_full_install` auf (s. 1.5).
  Ist nur die Minimal-Version installiert (`INSTALL_MODE=minimal`), erscheint statt eines
  `fzf: command not found`-Crashs eine klare Meldung: „Das interaktive Menü ist nur in der
  Vollinstallation verfügbar. Führe `install.sh --full` aus, um zu wechseln.“ Zusätzlich prüft
  `require_fzf`, ob `fzf` trotz `INSTALL_MODE=full` tatsächlich vorhanden ist (z. B. falls jemand
  es manuell deinstalliert hat) – auch das mit eigener, verständlicher Fehlermeldung statt Crash.

### 5.5 `basher run <name-or-path> [--repo <owner/repo>]`
Führt ein Script aus, ohne es zu öffnen. Ohne `--repo` wird das konfigurierte `REPO_PATH`
genutzt (lokal, Voll-Modus). Mit `--repo` (oder `BASHER_REPO`-Env) wird stattdessen ad-hoc ein
beliebiges öffentliches GitHub-Repo angesprochen (s. 3.4) – zentral für den curl-Minimal-Fall:
`curl -fsSL <raw-url> | bash -s -- --repo someone/their-scripts run tools/backup.sh` – lädt
`manifest.idx`, löst Pfad auf, curlt die Rohdatei in eine temporäre Datei, `chmod +x`, ausführen,
danach aufräumen.

### 5.6 `basher config …`
Siehe 2.4.

### 5.7 `basher repo …`
- `basher repo set <url>` – siehe 3.3
- `basher repo sync` – siehe 3.5 (Verhalten abhängig von `SYNC_MODE`: `auto` = pull --rebase +
  push, `pro` = nur Status anzeigen)

### 5.8 `install.sh` / `uninstall.sh`
- `install.sh [--minimal|--full]`: installiert `bin/basher` nach `~/.local/bin/basher` (kein
  `sudo` nötig, portabler). Voll-Modus prüft/installiert `fzf` über den erkannten Paketmanager.
  Fragt außerdem interaktiv, ob `AUTO_COMMIT` aktiviert werden soll (Default: **Nein**), und
  schreibt die Antwort direkt in die neu angelegte Config.
- `uninstall.sh`: entfernt nur den Tool-Teil. Fragt **explizit** nach, ob Scripts/Config/Secrets
  ebenfalls gelöscht werden sollen – Default ist **Behalten**, nie stillschweigend löschen.

### 5.9 Optional für später (v1.1, nicht Kern-Scope)
- `basher update` – Tool selbst aktualisieren (re-clone/re-curl der neuesten install.sh)
- `basher doctor` – prüft Abhängigkeiten, Rechte, Config-Validität
- `basher --version`

---

## 6. Subcommand-Referenztabelle

| Command | Zweck | Minimal-Modus | Voll-Modus |
|---|---|---|---|
| `basher tmp` | temporäres Script erstellen & ausführen | ✅ | ✅ |
| `basher new` | neues benanntes Script erstellen | ✅ | ✅ |
| `basher edit <x>` | bestehendes Script bearbeiten | ✅ (nur mit Namen) | ✅ (+ fzf-Picker) |
| `basher list` | Textliste aller Scripts | ✅ | ✅ |
| `basher menu` / `basher` | interaktives fzf-Menü (Enter=ausführen, Ctrl-E=bearbeiten) | ❌ | ✅ |
| `basher run <x>` | Script ausführen ohne Editor | ✅ | ✅ |
| `basher config …` | Config lesen/setzen | ✅ (get/set) | ✅ (+ interaktiv) |
| `basher repo …` | Repo setzen & synchronisieren (`set`, `sync`) | ✅ (`set`; curl: `--repo`-Override) | ✅ |
| `install.sh` | Installation | ✅ | ✅ |
| `uninstall.sh` | Deinstallation | ✅ | ✅ |

---

## 7. Repo-Struktur des basher-Tools (Vorschlag)

```
basher/
├── install.sh
├── uninstall.sh
├── bin/
│   └── basher              # Haupt-Entrypoint, nur Dispatcher (s. 1.4)
├── lib/
│   ├── core.sh              # gemeinsame Funktionen
│   ├── checks.sh             # Guard-Funktionen: require_full_install, require_fzf, … (s. 1.5)
│   ├── config.sh
│   ├── repo.sh
│   ├── secrets.sh
│   ├── menu.sh               # fzf-spezifisch, nur im Voll-Modus geladen
│   └── commands/              # ein File pro Subcommand, je eine cmd_<name>()-Funktion (s. 1.4)
│       ├── new.sh
│       ├── tmp.sh
│       ├── edit.sh
│       ├── list.sh
│       ├── menu.sh
│       ├── run.sh
│       ├── config.sh
│       └── repo.sh
├── minimal/
│   └── basher-minimal.sh     # self-contained Single-File-Variante für curl-Pipe (gleiches
│                              # cmd_*-Namensschema, physisch aber in einer Datei gebündelt)
└── README.md
```

---

## 8. Offene Punkte für dein Review

Bereits geklärt: Tmp-Lifecycle (5.1), Repo-Modell vereinfacht (3), Menü mit direkter Ausführung
(5.4), Autocommit-Default `false` + Abfrage bei Install (2.2/5.8), manifest.idx-Pflicht bestätigt
(3.4), Sync-Verhalten `auto`/`pro` (3.5), `TMP_DIR` respektiert `$TMPDIR` mit Fallback (2.2),
Subcommand-Namen bestätigt, Erweiterbarkeit via Dispatcher- + Guard-Pattern (1.4/1.5).

**`INSTALL_MODE`** (finale Entscheidung): primär von `install.sh` gesetzt und nicht Teil des
normalen `basher config`-Walkthroughs (2.3), aber via `basher config set INSTALL_MODE <wert>`
technisch überschreibbar – bewusst als „Hintertür fürs Debugging“, nicht als beworbener Workflow.
Keine zusätzliche Guard-Logik nötig, die das verhindert.

Damit sind aus meiner Sicht keine offenen Architekturfragen mehr offen – bereit für den ersten
Implementierungsschritt (`bin/basher`-Grundgerüst, s. 1.4/1.5).

---

## 9. Backlog (nicht blockierend, für später vorgemerkt)

### 9.1 ~~Mehrdeutige Skriptnamen: Auswahlmenü statt Fehlermeldung~~ ✅ Erledigt
`basher_manifest_resolve` (`lib/manifest.sh`) bietet bei mehreren Treffern jetzt eine Auswahl an
(`basher_manifest_disambiguate`): `fzf` im Voll-Modus, nummerierte Liste per `read` im
Minimal-Modus - funktioniert dadurch auch im curl-Fall. Betrifft `edit`, `run` (lokal und remote).

### 9.2 Fix: `basher_die` beendete bei Aufruf aus Command-Substitutions nicht das ganze Skript
Gefunden beim Testen von `edit`/`menu` mit fehlendem Editor: `exit` innerhalb einer Funktion, die
per `$(...)` eingebunden ist (z.B. `editor="$(basher_resolve_editor)"`), beendet nur die Subshell
der Substitution - das Hauptskript lief mit leerem Rückgabewert einfach weiter statt abzubrechen.
Fix: `basher_die` (`lib/checks.sh`) sendet zusätzlich `kill -s TERM "$$"` (referenziert laut
Bash-Doku auch in Subshells immer die PID des äußersten Skripts), `bin/basher` sowie das
Minimal-Bundle-Template fangen `TERM` per Trap ab. Betraf potenziell jede `basher_die`-Nutzung
im Projekt, nicht nur den Editor-Fall - breite Regression über alle Kernbefehle durchgeführt.
