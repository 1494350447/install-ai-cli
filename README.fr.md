# install-ai-cli

[简体中文](README.md) | [English](README.en.md) | [Deutsch](README.de.md) | [Français](README.fr.md)

Installateur Linux en une commande pour **Codex CLI** / **Claude Code** / **opencode** / **DeepSeek Harness (dsh)** / **OpenClaw**, conçu pour l'environnement réseau de la Chine continentale.

Un script bash sans dépendances qui règle d'un coup les pièges rencontrés lors de l'installation de ces outils dans cet environnement : version de Node trop ancienne, npm inaccessible, échec du téléchargement des binaires de plateforme, connexions GitHub réinitialisées.

> dsh et openclaw ne sont pas du même type que les trois premiers : après l'installation, ils **doivent encore être démarrés manuellement** — ce ne sont pas des CLI qui se terminent à la fin de la commande (dsh est un service web permanent, openclaw une passerelle). Aucun des deux n'est donc inclus dans `all`. Voir leurs sections respectives ci-dessous.

## Fonctionnalités

- **Vérification préalable** : affiche d'abord l'état de chaque outil ; les outils déjà installés ne sont **pas écrasés silencieusement** : le script demande pour chacun « désinstaller et réinstaller ? » (`y` / `N` / `a` / `q`)
- **Triple repli pour Node** : nvm (miroir Gitee) → installation directe du tarball npmmirror → erreur explicite avec un guide manuel
- **Ne modifie pas votre registre npm global** : `--registry` n'est utilisé que temporairement pendant l'installation. Pour le modifier définitivement, passez explicitement `--set-registry`
- **Pas de sudo** : les paquets globaux vont toujours dans `~/.npm-global`, ce qui évite que les paquets appartiennent à root et n'imposent sudo lors des mises à jour ultérieures
- **Triple repli du registre npm** : npmmirror → Tencent Cloud → officiel
- **Compatible avec toutes les distributions** : apt / dnf / yum / pacman / apk / zypper
- **Idempotent** : réexécutable sans risque, les outils déjà installés ne sont pas réinstallés

## Démarrage rapide

```bash
# Téléchargement
curl -fsSL <URL raw de ce dépôt>/install-ai-cli.sh -o install-ai-cli.sh

# Lancez d'abord un diagnostic pour voir l'état actuel
bash install-ai-cli.sh doctor

# Installation
bash install-ai-cli.sh codex
bash install-ai-cli.sh all
```

> Ce dépôt est **privé** ; un curl direct sur le lien raw nécessite un token. L'authentification pourra être supprimée une fois le dépôt public.

## Commandes

| Commande | Rôle |
|---|---|
| `codex` | Installer OpenAI Codex CLI |
| `claude` | Installer Claude Code |
| `opencode` | Installer opencode |
| `dsh` | Installer DeepSeek Harness |
| `openclaw` | Installer OpenClaw |
| `all` | Installer les trois CLI ci-dessus (**sans dsh / openclaw**) |
| `doctor` | Diagnostic : système, Node/npm, état des outils, connectivité réseau |
| `version` | Afficher la version du script |
| `help` | Aide |

`dsh` et `openclaw` prennent aussi en charge `--uninstall`, et tous deux **ne retirent que le paquet npm, sans jamais toucher aux données utilisateur** : `~/.dsh` (profils et sessions) et `~/.openclaw` (configuration, agents, workspace, état sqlite) ne sont jamais touchés par le script.

Lors d'une installation isolée d'`openclaw`, si vous ne passez pas explicitement `--node-major`, le script **fait automatiquement passer Node en 24** — il exige `>=24.16.0 <25 || >=26.1.0`, et la version 22 par défaut s'installe mais ne démarre pas.

## Options

| Option | Description |
|---|---|
| `--reinstall` / `-f` / `--force` / `--upgrade` | Ignorer les questions ; désinstaller et réinstaller tout ce qui est déjà installé |
| `-y` / `--yes` | Non interactif : ignorer tout ce qui est déjà installé, sans réinstallation |
| `--uninstall` | Désinstaller l'outil indiqué (conserve les fichiers de configuration, ne retire que les binaires) |
| `--registry <URL>` | Registre npm, par défaut `https://registry.npmmirror.com` |
| `--node-mirror <URL>` | Source des binaires Node |
| `--node-major <N>` | Version majeure de Node, par défaut 22 |
| `--no-node` | Ignorer l'installation/mise à jour de Node (à utiliser si Node ≥ 22 est déjà installé) |
| `--native` | Installer Claude Code via l'installateur curl officiel (npm par défaut ; plus fiable en Chine continentale) |
| `--set-registry` | Écrire durablement le registre global npm (la configuration globale n'est pas modifiée par défaut) |
| `--proxy <URL>` | Utiliser un proxy, par ex. `http://127.0.0.1:7897` |
| `-n` / `--dry-run` | Afficher les commandes qui seraient exécutées, sans rien modifier |
| `-v` / `--verbose` | Afficher chaque commande exécutée |

## Comportement lorsque l'outil est déjà installé

Le script n'écrase jamais silencieusement une installation existante. Il effectue d'abord une vérification préalable :

```
── Vérification préalable ──
  codex     non installé
  claude    installé  2.1.278      installateur officiel  /home/u/.local/bin/claude
  opencode  installé  1.18.31      npm                    /home/u/.local/bin/opencode
```

Puis il demande séparément pour chaque outil installé :

```
claude est installé : 2.1.278 (installateur officiel)
  Désinstaller et réinstaller ?
    [y] désinstaller et réinstaller    [N] ignorer    [a] réinstaller aussi les autres outils installés    [q] quitter
  Choix [y/N/a/q] >
```

- Entrée = ignorer ; seul `y`/`yes` déclenche une réinstallation
- `a` évite d'être interrogé trois fois de suite en mode `all`
- Dans un environnement non interactif (`-y`, CI, pas de terminal de contrôle), les outils déjà installés sont ignorés automatiquement avec un conseil d'ajouter `--upgrade`
- La désinstallation **ne supprime que des chemins explicites**, en journalisant chaque suppression ; les fichiers de configuration sont toujours conservés

## Environnements pris en charge

- **Distributions** : Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Fedora, Arch, Alpine, openSUSE
- **Architectures** : x86_64, aarch64/arm64, armv7l, ppc64le, s390x
- **Node** : ≥ 22 requis (installé automatiquement par le script). Il n'existe pas de build Node officiel pour LoongArch ; le script signale une erreur explicite et vous invite à utiliser `--no-node`
- **Node (dsh uniquement)** : dsh exige `^22.19.0 || >=24.0.0`, une contrainte plus stricte que ci-dessus. Le script le vérifie séparément et explique quoi faire si la condition n'est pas remplie. À noter : **Node 23.x est refusé** — il satisfait `>=22` mais sort de `>=24.0.0`
- **Node (openclaw uniquement)** : openclaw exige `>=24.16.0 <25 || >=26.1.0`, encore plus étrange que dsh — **la série 24.x exige au minimum le correctif `.16`, et toute la série 25.x est exclue**. Ainsi 22.x / 23.x / 24.0–24.15 / 25.x ne démarrent pas. Lors d'une installation isolée d'openclaw sans `--node-major` explicite, le script fait passer Node en 24 (actuellement la plus haute est 24.21.0, dans la plage)

## Les pièges du réseau en Chine continentale (déjà gérés)

**1. Le registre npm officiel est inaccessible** → utiliser npmmirror, basculer automatiquement vers Tencent Cloud en cas d'échec, puis vers le registre officiel.

**2. Les binaires Node sont difficiles à télécharger** → nvm lui-même est cloné depuis le miroir Gitee ; les tarballs Node viennent de npmmirror. **Attention : la liste du répertoire `latest-vN.x/` est un instantané obsolète** : lors des tests, `latest-v24.x/` de npmmirror ne listait que jusqu'à 24.9.0, alors que 24.10.0–24.21.0 existent réellement et sont téléchargeables sous `vX.Y.Z/` (contrôle : `v24.99.99/` et `v23.99.0/` renvoient tous deux 404, ce qui confirme que ces 200 ne sont pas des réponses aveugles). Le script lit donc plutôt `index.json` pour déterminer la version de patch la plus élevée — ce fichier est complet (866 entrées sur npmmirror, 863 sur Tencent ; nvm le lit aussi) — puis construit l'URL de téléchargement sous `vX.Y.Z/`. Ce n'est que lorsqu'un miroir ne fournit pas `index.json` qu'il revient à cette liste obsolète, avec un avertissement explicite.

**3. `npmmirror.com/mirrors/node/...` est une redirection 302**, et la suivre ne donne aucune liste de fichiers analysable. Pour récupérer la liste, utilisez `https://registry.npmmirror.com/-/binary/node/...`. (`index.json` est aussi une 302 vers le CDN ; les téléchargements et les sondes du script utilisent tous `-L`.)

**4. Les GitHub Releases sont pratiquement inaccessibles en direct** → tous les outils privilégient les paquets npm (les binaires de plateforme sont livrés via les optionalDependencies npm) au lieu de récupérer des artefacts de release depuis GitHub. Le `dist/` d'openclaw est un paquet autonome ; tous les liens github.com dans `dist/` sont des références à la documentation ou à des issues, sans point de téléchargement.

## À faire après l'installation

Le script ne résout que le problème du **téléchargement**, pas celui de la **capacité à fonctionner**. Ces outils nécessitent tous une configuration de l'URL d'API et de la clé après l'installation, et les points de terminaison officiels sont généralement inaccessibles en direct en Chine continentale :

| Outil | Fichier de configuration |
|---|---|
| codex | `~/.codex/config.toml` |
| claude | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.jsonc` |
| dsh | `~/.dsh/` (répertoire des profils et sessions) |
| openclaw | `~/.openclaw/` (répertoire de `openclaw.json`, `.env`, `agents/`, `workspace`, état sqlite) |

La colonne « Connectivité » de `bash install-ai-cli.sh doctor` vous indique quels points de terminaison sont joignables et lesquels ne le sont pas.

## Utiliser dsh

Le script ne gère que l'**installation**, pas l'exécution. Lancez-le vous-même après l'installation :

```bash
dsh web --host 127.0.0.1 --port 3080
```

- Il affiche dans le terminal une **URL contenant un token** ; copiez-la dans un navigateur
- **S'exécute au premier plan** ; `Ctrl-C` l'arrête
- Pour changer de port, modifiez `--port`

Deux autres choses :

1. **Définissez `DEEPSEEK_API_KEY`**, sinon l'interface s'ouvre mais ne peut pas appeler les modèles. `doctor` vous indique si elle est définie.
2. **`--host 0.0.0.0` n'est pas pris en charge** ; dsh renvoie directement une erreur. Il n'accepte que `127.0.0.1` ou une adresse d'interface concrète.

> La gestion des versions, la journalisation, le démarrage automatique et les fonctions similaires pour dsh ne relèvent pas de ce script. `dsh -h` et `dsh web --help` sont l'aide propre à l'upstream.

## Utiliser openclaw

Là encore, installation uniquement. Configurez-le une fois après l'installation, puis démarrez la passerelle :

```bash
openclaw onboard     # configuration initiale (modèles, canaux, etc.)
openclaw gateway     # démarre la passerelle au premier plan ; Ctrl-C l'arrête
```

Si vous ne voulez pas lancer le service et que vous souhaitez juste poser une question :

```bash
openclaw agent --message "..."
```

Pour le dépannage, utilisez `openclaw doctor` et `openclaw status` ; `--help` / `--version` sont l'aide propre à l'upstream.

Quelques rappels :

1. **La configuration, les agents, le workspace et l'état sqlite se trouvent tous dans `~/.openclaw`**. La désinstallation ne retire que le paquet npm et ne touche jamais à ce répertoire.
2. **Il est volumineux** : le tarball fait environ 72 Mo, et environ 222 Mo une fois décompressé (plus de 6 700 fichiers sous `dist/`). L'installation prend nettement plus de temps que les autres.
3. **La contrainte Node est étrange** : `>=24.16.0 <25 || >=26.1.0`. 25.x est explicitement exclu, et 24.x nécessite `.16` ou plus.

## Limitations connues

- **La voie npm de Claude Code a été dépréciée par l'éditeur** (depuis janvier 2026). Le paquet fonctionne encore mais ne se met plus à jour automatiquement ; les mises à jour nécessitent de relancer `--upgrade`. Pour une installation native, ajoutez `--native`.
- **npm 12 bloque par défaut les scripts d'installation** (`postinstall`). codex / claude / opencode comptent sur `postinstall` pour lier les binaires de plateforme dans `bin/`, et le `postinstall` d'openclaw supprime les fichiers obsolètes sous `dist/` — un blocage peut laisser un état « fonctionnel mais incomplet ». Le script **ne gère pas encore ce point** — `--version` n'est pas une vérification fiable pour ces paquets. npm 11.16–11.x ne fait qu'avertir et exécute les scripts, il n'est donc pas affecté.
- **Si une version plus ancienne est trouvée en premier dans le PATH après l'installation du paquet** (par exemple installée par le gestionnaire de paquets du système), le script avertit mais ne la désinstalle pas à votre place.
- **dsh est actuellement un aperçu développeur** (publié sur npm en `-rc` / `-alpha`) ; l'upstream le marque explicitement comme developer preview et son comportement peut changer.
- **Ne pas sonder la version de dsh avec `dsh --version`** : c'est un lanceur d'application, et l'upstream précise que « les arguments que le lanceur ne reconnaît pas sont transmis au profil » ; l'exécuter directement peut réellement démarrer un profil web et bloquer la vérification préalable. Le script lit plutôt le `package.json` du paquet installé, et ne revient à `--version` (avec un délai de 5 secondes) que si cette lecture échoue.
- **L'arbre de dépendances de dsh est volumineux** (73 dépendances de production). Lors du parcours, aucune ne manquait sur les miroirs de Chine continentale, mais l'installation est plus lente que celle de codex / claude / opencode.
- **dsh est installé uniquement à partir du paquet précompilé npm ; aucune compilation depuis les sources n'est fournie**. Ce script ne clone pas le dépôt, n'installe pas pnpm et ne compile pas. Pour modifier les sources de dsh, clonez l'upstream vous-même.
- **openclaw est installé uniquement à partir du paquet npm**, sans compilation depuis les sources (l'upstream propose aussi `openclaw.ai/install.sh`, que ce script n'utilise pas).
- **openclaw ne démarre pas tout seul après l'installation**, et c'est une **passerelle / service permanent** (canaux Telegram, Discord, Slack, WhatsApp, etc. + contrôle du navigateur + cron), pas un CLI qui se termine une fois lancé. Le script ne fait qu'installer.
- **Les dépendances transitives d'openclaw n'ont pas été vérifiées de manière exhaustive**. Seules ses 66 dépendances **directes** ont été vérifiées version par version quant à leur disponibilité complète sur les miroirs de Chine continentale ; npmmirror synchronise tout, le risque est donc faible, mais non prouvé.
- **Le `bin/` et la détection de `--version` d'openclaw sont fiables** (la documentation upstream précise que `--help` / `--version` empruntent un chemin rapide), il n'a donc pas besoin du contournement par `package.json` nécessaire pour dsh.

## État

- **Résolution de version Node (v1.2.1)** : auparavant, la version de patch la plus élevée était choisie dans la liste `latest-vN.x/`, mais cette liste est obsolète sur les miroirs — `--node-major 24` installait 24.9.0 au lieu de 24.21.0. Il lit désormais `index.json`. Téléchargement et décompression réels de 24.21.0 sous Git Bash (`node_version.h` confirmé à 24.21.0), et chemin de repli vérifié séparément (simulation d'un miroir sans `index.json`, confirmation de l'avertissement et du repli correct vers l'ancienne disposition)
- Vérifié sous Git Bash sur Windows : syntaxe, `doctor`, `--dry-run`, `--uninstall`, saut non interactif, analyse des réponses (`y/N/a/q`)
- Installation réelle d'opencode via la voie npm sous Linux (npm 11.19.0 / Node v24.21.0)
- **Partie dsh** : 9 cas de version pour `node_satisfies_dsh` (dont le Node 23.x qui doit être refusé), les chemins d'intégration installation/désinstallation, et « la désinstallation ne doit pas toucher `~/.dsh` », tous exécutés avec de faux node/npm + un HOME isolé
- **Partie openclaw (v1.3.0)** : 13 cas de version pour `node_satisfies_openclaw` (dont les 25.x et 24.15 qui doivent être refusés), les quatre scénarios d'élévation automatique de Node (installation isolée / `--node-major 22` explicite / 26 explicite / pas d'élévation lors de l'installation de dsh), et un test en bac à sable de « la désinstallation ne doit pas toucher `~/.openclaw` ». Un vrai bug a été trouvé et corrigé pendant les tests : `27.0.0` devrait être accepté par `>=26.1.0`, mais l'implémentation d'origine le refusait car elle était écrite comme « majeur ≥ 26 et mineur ≥ 1 »
- **Tous les chemins d'écriture n'ont pas encore été exécutés de bout en bout dans un environnement Linux complet** (`nvm install`, `tar -xJf`, les installations npm de chaque outil)
- **L'installation npm de dsh et le démarrage de `dsh web` n'ont pas encore été exécutés sur une machine réelle**. L'installabilité de `@deepseek-ai/dsh` a été vérifiée au niveau des métadonnées npm (73 dépendances de production sans aucune lacune sur les miroirs de Chine continentale, binaires de plateforme correctement livrés via les optionalDependencies), mais une confirmation finale sur machine réelle reste nécessaire
- **L'installation npm d'openclaw et le démarrage de `openclaw gateway` n'ont pas encore été exécutés sur une machine réelle**. De même, vérifiés uniquement au niveau des métadonnées npm (66 dépendances directes à versions exactes sans lacune sur les miroirs de Chine continentale ; les liens github.com dans `dist/` sont des références documentaires et non des points de téléchargement), et le téléchargement puis la décompression réels du paquet de 72 Mo nécessitent encore une confirmation sur machine réelle

## Licence

Non spécifiée.
