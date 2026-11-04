# install-ai-cli

[简体中文](README.md) | [English](README.en.md) | [Deutsch](README.de.md) | [Français](README.fr.md)

Ein Linux-Installer für **Codex CLI** / **Claude Code** / **opencode** / **DeepSeek Harness (dsh)** / **OpenClaw**, der mit einem einzigen Befehl auskommt und auf die Netzwerkumgebung in Festlandchina ausgelegt ist.

Ein abhängigkeitsfreies Bash-Skript, das die Stolperfallen beim Installieren dieser Tools in dieser Umgebung in einem Durchgang beseitigt: zu altes Node, nicht erreichbares npm, fehlschlagende Downloads von Plattform-Binärdateien, zurückgesetzte GitHub-Verbindungen.

> dsh und openclaw sind keine Tools derselben Art wie die ersten drei: Nach der Installation **müssen sie noch manuell gestartet werden** — es sind keine CLIs, die mit der Rückkehr des Befehls enden (dsh ist ein dauerhaft laufender Webdienst, openclaw ein Gateway). Deshalb ist **keines von beiden in `all` enthalten**. Siehe die jeweiligen Abschnitte weiter unten.

## Funktionen

- **Vorabprüfung zuerst**: listet den aktuellen Stand jedes Tools auf; bereits installierte Tools werden **nicht stillschweigend überschrieben**, sondern einzeln gefragt „Deinstallieren und neu installieren?“ (`y` / `N` / `a` / `q`)
- **Dreistufiger Node-Fallback**: nvm (Gitee-Mirror) → direkte Installation aus dem npmmirror-Tarball → ausdrücklicher Fehler mit manueller Anleitung
- **Ihre globale npm-Registry bleibt unberührt**: `--registry` wird nur während der Installation vorübergehend verwendet. Für eine dauerhafte Änderung explizit `--set-registry` angeben
- **Kein sudo**: globale Pakete landen immer in `~/.npm-global`, damit spätere Upgrades nicht wegen root-Besitz sudo benötigen
- **Dreistufiger npm-Registry-Fallback**: npmmirror → Tencent Cloud → offiziell
- **Funktioniert auf jeder Distribution**: apt / dnf / yum / pacman / apk / zypper
- **Idempotent**: gefahrlos wiederholbar, bereits installierte Tools werden nicht erneut installiert

## Schnellstart

```bash
# Herunterladen
curl -fsSL <Raw-URL dieses Repos>/install-ai-cli.sh -o install-ai-cli.sh

# Zuerst einen Check ausführen und den aktuellen Stand ansehen
bash install-ai-cli.sh doctor

# Installieren
bash install-ai-cli.sh codex
bash install-ai-cli.sh all
```

> Dieses Repository ist **privat**; der direkte curl-Aufruf der Raw-URL erfordert ein Token. Nach der Veröffentlichung kann die Authentifizierung entfallen.

## Befehle

| Befehl | Zweck |
|---|---|
| `codex` | OpenAI Codex CLI installieren |
| `claude` | Claude Code installieren |
| `opencode` | opencode installieren |
| `dsh` | DeepSeek Harness installieren |
| `openclaw` | OpenClaw installieren |
| `all` | Alle drei obigen CLIs installieren (**ohne dsh / openclaw**) |
| `doctor` | Check: System, Node/npm, Tool-Status, Netzwerkverbindung |
| `version` | Skriptversion ausgeben |
| `help` | Hilfe |

`dsh` und `openclaw` unterstützen ebenfalls `--uninstall`, und beide **entfernen nur das npm-Paket, niemals Benutzerdaten**: `~/.dsh` (Profile und Sitzungen) und `~/.openclaw` (Konfiguration, Agents, Workspace, SQLite-Status) werden vom Skript nie angefasst.

Wird `openclaw` allein installiert, ohne dass `--node-major` ausdrücklich angegeben wird, **hebt das Skript Node automatisch auf 24** — es verlangt `>=24.16.0 <25 || >=26.1.0`, und die standardmäßige 22 wird zwar installiert, startet aber nicht.

## Optionen

| Option | Beschreibung |
|---|---|
| `--reinstall` / `-f` / `--force` / `--upgrade` | Rückfragen überspringen; alles bereits Installierte deinstallieren und neu installieren |
| `-y` / `--yes` | Nicht interaktiv: alles bereits Installierte überspringen, nicht neu installieren |
| `--uninstall` | Das angegebene Tool deinstallieren (Konfigurationsdateien bleiben erhalten, nur Binärdateien werden entfernt) |
| `--registry <URL>` | npm-Registry, Standard `https://registry.npmmirror.com` |
| `--node-mirror <URL>` | Node-Binärquelle |
| `--node-major <N>` | Node-Hauptversion, Standard 22 |
| `--no-node` | Node-Installation/-Upgrade überspringen (wenn Node ≥ 22 bereits installiert ist) |
| `--native` | Claude Code über den offiziellen curl-Installer installieren (standardmäßig npm; in Festlandchina zuverlässiger) |
| `--set-registry` | Die globale npm-Registry dauerhaft schreiben (standardmäßig wird die globale Konfiguration nicht geändert) |
| `--proxy <URL>` | Proxy verwenden, z. B. `http://127.0.0.1:7897` |
| `-n` / `--dry-run` | Die auszuführenden Befehle ausgeben; keine Änderungen vornehmen |
| `-v` / `--verbose` | Jeden ausgeführten Befehl ausgeben |

## Verhalten bei bereits installierten Tools

Das Skript überschreibt eine vorhandene Installation nie stillschweigend. Zuerst läuft eine Vorabprüfung:

```
── Vorabprüfung ──
  codex     nicht installiert
  claude    installiert  2.1.278   offizieller Installer  /home/u/.local/bin/claude
  opencode  installiert  1.18.31   npm                    /home/u/.local/bin/opencode
```

Danach wird für jedes installierte Tool einzeln gefragt:

```
claude ist installiert: 2.1.278 (offizieller Installer)
  Deinstallieren und neu installieren?
    [y] deinstallieren und neu installieren    [N] überspringen    [a] auch die übrigen installierten Tools neu installieren    [q] beenden
  Auswahl [y/N/a/q] >
```

- Enter = überspringen; nur `y`/`yes` löst eine Neuinstallation aus
- `a` erspart im `all`-Modus drei Rückfragen hintereinander
- In einer nicht interaktiven Umgebung (`-y`, CI, kein steuerndes Terminal) werden bereits installierte Tools automatisch übersprungen, mit dem Hinweis, `--upgrade` zu ergänzen
- Beim Deinstallieren werden **nur die ausdrücklich festgelegten Pfade gelöscht**, jede Löschung wird protokolliert; Konfigurationsdateien bleiben immer erhalten

## Unterstützte Umgebungen

- **Distributionen**: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Fedora, Arch, Alpine, openSUSE
- **Architekturen**: x86_64, aarch64/arm64, armv7l, ppc64le, s390x
- **Node**: ≥ 22 erforderlich (wird vom Skript automatisch installiert). Für LoongArch gibt es keinen offiziellen Node-Build; das Skript meldet einen ausdrücklichen Fehler und empfiehlt `--no-node`
- **Node (nur dsh)**: dsh verlangt `^22.19.0 || >=24.0.0`, strenger als oben. Das Skript prüft das separat und erklärt, was bei Nichterfüllung zu tun ist. Beachten Sie, dass **Node 23.x abgelehnt wird** — es erfüllt `>=22`, liegt aber außerhalb von `>=24.0.0`
- **Node (nur openclaw)**: openclaw verlangt `>=24.16.0 <25 || >=26.1.0`, noch seltsamer als dsh — **24.x hat eine Patch-Untergrenze von `.16`, und die gesamte 25.x-Reihe ist ausgeschlossen**. Somit starten 22.x / 23.x / 24.0–24.15 / 25.x nicht. Wird openclaw allein ohne ausdrückliches `--node-major` installiert, hebt das Skript Node auf 24 (derzeit ist 24.21.0 die höchste Version und liegt im Bereich)

## Netzwerk-Fallstricke in Festlandchina (bereits behandelt)

**1. Die offizielle npm-Registry ist nicht erreichbar** → npmmirror verwenden; bei Fehler automatisch zu Tencent Cloud und dann zur offiziellen Registry wechseln.

**2. Node-Binärdateien lassen sich schwer herunterladen** → nvm selbst wird vom Gitee-Mirror geklont; Node-Tarballs kommen von npmmirror. **Beachten Sie, dass das Verzeichnislisting `latest-vN.x/` ein veralteter Schnappschuss ist**: Im Test listete npmmirror unter `latest-v24.x/` nur bis 24.9.0, während 24.10.0–24.21.0 unter `vX.Y.Z/` tatsächlich existieren und herunterladbar sind (Kontrolle: `v24.99.99/` und `v23.99.0/` liefern beide 404, was bestätigt, dass die 200er keine pauschalen Antworten sind). Daher liest das Skript stattdessen `index.json`, um die höchste Patchversion zu ermitteln — diese Datei ist vollständig (866 Einträge auf npmmirror, 863 auf Tencent; auch nvm liest sie) — und setzt dann die Download-URL unter `vX.Y.Z/` zusammen. Nur wenn ein Mirror kein `index.json` bereitstellt, wird auf das veraltete Listing zurückgefallen, mit ausdrücklicher Warnung.

**3. `npmmirror.com/mirrors/node/...` ist eine 302-Weiterleitung**, und beim Folgen erhält man kein auswertbares Dateilisting. Für das Listing muss `https://registry.npmmirror.com/-/binary/node/...` verwendet werden. (`index.json` ist ebenfalls eine 302 zum CDN; alle Downloads und Prüfungen des Skripts verwenden `-L`.)

**4. GitHub Releases sind praktisch nicht direkt erreichbar** → alle Tools bevorzugen npm-Pakete (Plattform-Binärdateien werden über npm optionalDependencies ausgeliefert), statt Release-Artefakte von GitHub zu laden. Das `dist/` von openclaw ist ein eigenständiges Bundle; alle github.com-Links darin sind Dokumentations- oder Issue-Verweise, kein Download-Endpunkt.

## Was nach der Installation zu tun ist

Das Skript löst nur das **Download**-Problem, nicht die Frage, **ob das Tool tatsächlich läuft**. Diese Tools benötigen nach der Installation jeweils einen eigenen API-Endpunkt und Schlüssel, und die offiziellen Endpunkte sind in Festlandchina meist nicht direkt erreichbar:

| Tool | Konfigurationsdatei |
|---|---|
| codex | `~/.codex/config.toml` |
| claude | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.jsonc` |
| dsh | `~/.dsh/` (Verzeichnis für Profile und Sitzungen) |
| openclaw | `~/.openclaw/` (Verzeichnis für `openclaw.json`, `.env`, `agents/`, `workspace`, SQLite-Status) |

Die Spalte „Konnektivität“ von `bash install-ai-cli.sh doctor` zeigt, welche Endpunkte erreichbar sind und welche nicht.

## dsh verwenden

Das Skript kümmert sich nur um die **Installation**, nicht um den Betrieb. Nach der Installation selbst starten:

```bash
dsh web --host 127.0.0.1 --port 3080
```

- Es gibt im Terminal eine **URL mit Token** aus; kopieren Sie diese in den Browser
- **Läuft im Vordergrund**; `Ctrl-C` beendet den Prozess
- Der Port lässt sich mit `--port` ändern

Zwei weitere Punkte:

1. **`DEEPSEEK_API_KEY` setzen**, sonst öffnet sich die Oberfläche, kann aber keine Modelle aufrufen. `doctor` zeigt an, ob die Variable gesetzt ist.
2. **`--host 0.0.0.0` wird nicht unterstützt**; dsh bricht direkt mit einem Fehler ab. Akzeptiert werden nur `127.0.0.1` oder eine konkrete Interface-Adresse.

> Versionsverwaltung, Logging, Autostart und Ähnliches für dsh sind nicht Teil dieses Skripts. `dsh -h` und `dsh web --help` sind die Hilfe des Upstreams.

## openclaw verwenden

Ebenfalls nur Installation. Nach der Installation einmal konfigurieren, dann das Gateway starten:

```bash
openclaw onboard     # Erstkonfiguration (Modelle, Kanäle usw.)
openclaw gateway     # Gateway im Vordergrund starten; Ctrl-C beendet es
```

Wenn Sie den Dienst nicht starten, sondern nur eine Frage stellen möchten:

```bash
openclaw agent --message "..."
```

Zur Fehlersuche `openclaw doctor` und `openclaw status` verwenden; `--help` / `--version` sind die Hilfe des Upstreams.

Einige Hinweise:

1. **Konfiguration, Agents, Workspace und SQLite-Status liegen alle in `~/.openclaw`**. Beim Deinstallieren wird nur das npm-Paket entfernt; dieses Verzeichnis wird nie angefasst.
2. **Es ist groß**: Der Tarball ist etwa 72 MB groß, entpackt etwa 222 MB (über 6.700 Dateien unter `dist/`). Die Installation dauert deutlich länger als bei den anderen.
3. **Die Node-Anforderung ist ungewöhnlich**: `>=24.16.0 <25 || >=26.1.0`. 25.x ist ausdrücklich ausgeschlossen, und 24.x benötigt mindestens `.16`.

## Bekannte Einschränkungen

- **Der npm-Weg für Claude Code wurde vom Hersteller als veraltet markiert** (seit Januar 2026). Das Paket funktioniert noch, wird aber nicht mehr automatisch aktualisiert; für Upgrades `--upgrade` erneut ausführen. Für eine native Installation `--native` ergänzen.
- **npm 12 blockiert Installationsskripte standardmäßig** (`postinstall`). codex / claude / opencode verlassen sich darauf, dass `postinstall` Plattform-Binärdateien nach `bin/` verlinkt, und openclaws `postinstall` bereinigt veraltete Dateien unter `dist/` — bei Blockierung kann ein Zustand entstehen, der „funktioniert, aber unvollständig“ ist. Das Skript **behandelt dies noch nicht** — `--version` ist für solche Pakete kein verlässlicher Check. npm 11.16–11.x warnt nur und führt Skripte weiterhin aus, ist also nicht betroffen.
- **Wenn nach der Paketinstallation eine ältere Version zuerst im PATH liegt** (z. B. vom System-Paketmanager installiert), warnt das Skript, deinstalliert sie aber nicht für Sie.
- **dsh ist derzeit eine Developer Preview** (npm veröffentlicht es als `-rc` / `-alpha`); der Upstream kennzeichnet es ausdrücklich als Developer Preview, das Verhalten kann sich ändern.
- **Die dsh-Version nicht mit `dsh --version` prüfen**: Es ist ein Anwendungsstarter, und der Upstream legt fest, dass „Argumente, die der Starter nicht kennt, an das Profil weitergegeben werden“; ein direkter Aufruf kann tatsächlich ein Web-Profil hochfahren und die Vorabprüfung aufhängen. Das Skript liest stattdessen die `package.json` des installierten Pakets und fällt nur dann auf `--version` zurück (mit 5-Sekunden-Timeout), wenn diese nicht lesbar ist.
- **Der Abhängigkeitsbaum von dsh ist groß** (73 Produktionsabhängigkeiten). Beim Crawling fehlte auf den chinesischen Mirrors nichts, die Installation dauert aber länger als bei codex / claude / opencode.
- **dsh wird nur aus dem vorgefertigten npm-Paket installiert; einen Build aus dem Quellcode gibt es nicht**. Dieses Skript klont kein Repository, installiert kein pnpm und kompiliert nicht. Um dsh-Quellcode zu ändern, klonen Sie den Upstream selbst.
- **openclaw wird nur aus dem npm-Paket installiert**, ohne Build aus dem Quellcode (der Upstream hat außerdem `openclaw.ai/install.sh`, das dieses Skript nicht verwendet).
- **openclaw startet sich nach der Installation nicht selbst**, und es ist ein **Gateway / dauerhaft laufender Dienst** (Telegram-, Discord-, Slack-, WhatsApp- und weitere Kanäle + Browsersteuerung + Cron), keine Fire-and-forget-CLI. Das Skript installiert nur.
- **Die transitiven Abhängigkeiten von openclaw wurden nicht erschöpfend geprüft**. Nur die 66 **direkten** Abhängigkeiten wurden Version für Version auf vollständige Verfügbarkeit auf chinesischen Mirrors geprüft; npmmirror synchronisiert alles, das Risiko ist gering, aber nicht belegt.
- **Die Prüfung von `bin/` und `--version` bei openclaw ist zuverlässig** (laut Upstream-Dokumentation nehmen `--help` / `--version` einen Fast Path), daher ist der `package.json`-Umweg von dsh hier nicht nötig.

## Status

- **Node-Versionsermittlung (v1.2.1)**: Zuvor wurde die höchste Patchversion aus dem Listing `latest-vN.x/` gewählt, aber dieses Listing ist auf Mirrors veraltet — `--node-major 24` installierte 24.9.0 statt 24.21.0. Jetzt wird `index.json` gelesen. Unter Git Bash wurde 24.21.0 tatsächlich heruntergeladen und entpackt (`node_version.h` bestätigte 24.21.0), und der Downgrade-Pfad wurde separat geprüft (Mirror ohne `index.json` simuliert, Warnung und korrekter Rückfall auf das alte Layout bestätigt)
- Unter Windows in Git Bash verifiziert: Syntax, `doctor`, `--dry-run`, `--uninstall`, nicht interaktives Überspringen, Antwortauswertung (`y/N/a/q`)
- opencode auf Linux tatsächlich über die npm-Route installiert (npm 11.19.0 / Node v24.21.0)
- **dsh-Teil**: 9 Versionsfälle für `node_satisfies_dsh` (einschließlich des abzulehnenden Node 23.x), die Integrationspfade für Installation/Deinstallation und „Deinstallation darf `~/.dsh` nicht anfassen“, alle mit Fake-node/npm + Sandbox-HOME ausgeführt
- **openclaw-Teil (v1.3.0)**: 13 Versionsfälle für `node_satisfies_openclaw` (einschließlich der abzulehnenden 25.x und 24.15), die vier Szenarien der automatischen Node-Heraufsetzung (Einzelinstallation / ausdrückliches `--node-major 22` / ausdrückliches 26 / kein Heraufsetzen bei dsh-Installation) und ein Sandbox-Test für „Deinstallation darf `~/.openclaw` nicht anfassen“. Beim Testen wurde ein echter Bug gefunden und behoben: `27.0.0` sollte von `>=26.1.0` akzeptiert werden, die ursprüngliche Implementierung lehnte es jedoch ab, weil sie als „Major ≥ 26 und Minor ≥ 1“ geschrieben war
- **Alle Schreibpfade wurden noch nicht in einer vollständigen Linux-Umgebung durchgängig ausgeführt** (`nvm install`, `tar -xJf`, die npm-Installationen der einzelnen Tools)
- **Die npm-Installation von dsh und der Start von `dsh web` wurden noch nicht auf echter Hardware ausgeführt**. Die Installierbarkeit von `@deepseek-ai/dsh` wurde auf npm-Metadatenebene geprüft (73 Produktionsabhängigkeiten ohne Lücken auf chinesischen Mirrors, Plattform-Binärdateien werden über optionalDependencies korrekt ausgeliefert), eine abschließende Bestätigung auf echter Hardware fehlt aber noch
- **Die npm-Installation von openclaw und der Start von `openclaw gateway` wurden noch nicht auf echter Hardware ausgeführt**. Ebenfalls nur auf npm-Metadatenebene geprüft (66 direkte Abhängigkeiten in exakten Versionen ohne Lücken auf chinesischen Mirrors; github.com-Links in `dist/` sind Dokumentationsverweise, keine Download-Endpunkte), und der tatsächliche Download und das Entpacken des 72-MB-Pakets benötigen noch eine Bestätigung auf echter Hardware

## Lizenz

Nicht angegeben.
