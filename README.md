<div align="center">

<img src="windows/runner/resources/app_icon.ico" width="96" alt="Icône Fractus">

# Fractus

**Toute la puissance dans une IA.**
Un petit compagnon qui vit en haut de l'écran et garde un œil sur vos agents de code
(Claude Code et les autres) : approuvez, répondez, discutez, sans quitter ce que vous faites.

Application **Windows** écrite en **Flutter**. L'interface reprend celle de
[Coucou](https://github.com/Louis-CFM/coucou) de Louis Raillé (Louis-CFM) : l'île en haut
de l'écran, les pastilles, les cartes de permission, de question et de fin, le chat. Le compagnon,
lui, s'appelle **Fractus** : un petit cristal aux grands yeux.

</div>

---

## Ce que ça fait

- 🏝️ **L'île** — une île noire collée en haut au centre de l'écran. Cachée quand il ne se passe
  rien, elle sort quand le pointeur touche le bord haut (bande de 240 × 6 px), s'ouvre au clic
  (ou au survol, dans les réglages) et se replie quand le pointeur s'en va. Tailles, rayons,
  courbes d'ouverture (`cubic-bezier(.32,1.22,.42,1)`, 520 ms) et de fermeture (340 ms) sont celles de Coucou.
- 💎 **Fractus** — un petit cristal aux grands yeux (« fractus » : éclat, en latin), dessiné en code
  (aucune image) : respiration,
  clignements, regard qui suit la souris, états `idle / working / thinking / searching / approval /
  question / error / finished / ratelimit / sleeping / dizzy`, badges, particules (étoiles, cœurs,
  sueur, z), le salut de la main au lancement, l'agacement quand on le tape (trois tapes : étourdi),
  les cœurs quand on reste sur lui deux secondes. Le moteur d'animation est un portage du `BotEngine` de Coucou.
- 🤖 **Les sessions en direct** — chaque session Claude Code a sa pastille colorée et son mini Fractus ;
  la carte montre le projet, l'agent et les dernières étapes (lecture, modification, commande, recherche).
- ✅ **Permissions et questions** — `PermissionRequest` s'affiche avec **Refuser (N) / Autoriser (Y) /
  Toujours** ; `AskUserQuestion` montre ses choix (jusqu'à 4 questions, sélection multiple).
  Jamais rien d'autorisé sans un clic ; sans réponse, le terminal reprend la main.
- 🎉 **Terminé / erreur** — Fractus fait sa roulade, la carte verte résume la réponse.
- 🤖 **Fractus pilote votre PC et code pour vous** — un seul compagnon, un vrai agent, avec votre clé
  **Groq** (gratuite) : le modèle le plus capable du compte choisi automatiquement (gpt-oss-120b, Kimi K2,
  Llama 3.3 70B…), raisonnement au maximum, réponses en streaming. Ses outils : **fichiers et code**
  (lire, chercher, écrire, modifier, PowerShell, URL) et **le PC** (ouvrir des applis/fichiers/URL,
  fenêtres, clavier, processus, presse-papiers, capture d'écran, volume, notifications,
  verrouiller / veille / redémarrer / éteindre) — et depuis la 0.5, **il voit l'écran et clique** :
  `look_at_screen` envoie une capture (avec une grille de coordonnées) à un modèle vision de Groq qui lui
  dit ce qui est affiché et où, puis `click` / `scroll` / `drag` font le reste. Chaque action passe par la carte
  **Autoriser / Refuser / Toujours** de l'île ; son travail apparaît comme la session « Fractus ».
- 🧠 **Il se souvient** (0.6) — les conversations sont gardées sur disque (historique et « Nouvelle
  conversation » dans le chat, la dernière est rouverte au lancement) ; une **mémoire longue**
  `memoire.md`, relue à chaque conversation, que Fractus enrichit lui-même (`remember` / `forget`, sous
  permission) et que vous pouvez éditer à la main ; et un **journal d'activité** (onglet ⟲) qui liste
  tout ce qu'il a fait, avec une copie de chaque fichier avant modification et un bouton **Annuler**.
- 📱 **Fractus sur le téléphone** (0.7, Android) — l'appli `Fractus-Android.apk` (dans chaque Release) se connecte
  au PC sur le réseau local : état de Fractus et des autres agents en direct, **Autoriser / Refuser / Toujours**
  à distance (et réponses aux questions), chat avec Fractus (il agit sur le PC), **écran du PC** en direct,
  actions rapides (verrouiller, veille, son, volume, lecture). Deux **widgets d'écran d'accueil** : boutons, et
  état + demande en attente + dernière réponse. Appairage par adresse + code (Réglages → Téléphone sur le PC).
- 🌌 **Thème Aurora** — noir bleuté profond, surfaces teintées, accent cyan → violet en dégradé sur les
  boutons et en lueur diffuse derrière les cartes.
- ⚙️ **Réglages dans l'île** — survol, son, lancement avec Windows, port des hooks, clé API, mises à jour, quitter.
- 🫥 **En arrière-plan** — pas de fenêtre dans la barre des tâches : une icône dans la zone de
  notification (clic gauche : ouvrir l'île ; clic droit : réglages, mises à jour, quitter) et, par
  défaut, un lancement automatique avec Windows (désactivable dans les réglages).
- 🔄 **Mises à jour** — Fractus regarde les Releases GitHub au lancement puis toutes les 6 h ; quand
  une nouvelle version existe, l'île s'ouvre sur une carte **Installer / Plus tard**. L'installateur
  se télécharge, se lance en silencieux, remplace les fichiers et relance Fractus.
- 🔒 **Privé** — aucune télémétrie, aucun compte. Le serveur de hooks n'écoute que sur `127.0.0.1` ;
  la seule requête sortante hors chat est le contrôle de version sur `api.github.com`.

## Le téléphone (Android)

1. Sur le PC : Fractus → ⚙️ Réglages → **Téléphone** → active « Autoriser le contrôle depuis le téléphone ».
   L'adresse (`192.168.x.x:7790`) et le code (`XXXX-XXXX`) s'affichent. Si le téléphone ne se connecte pas,
   clique **Pare-feu** une fois (ouvre le port sur les réseaux privés, demande les droits administrateur).
2. Sur le téléphone : installe `Fractus-Android.apk` (Release GitHub ; autoriser les sources inconnues),
   l'île s'ouvre sur ses réglages → **Scanner le QR code** (bouton **QR code** dans les réglages du PC),
   ou entre l'adresse et le code à la main → **Se connecter**.
3. Depuis l'extérieur : [Tailscale](https://tailscale.com) sur le PC et le téléphone, puis l'adresse Tailscale
   du PC (`100.x.x.x:7790`). Pas de serveur relais : rien ne transite ailleurs que entre tes deux appareils.

Dans les réglages du téléphone, deux options de plus :
- **Notifications** : un petit service natif garde le flux du PC ouvert même appli fermée (une notification
  discrète reste affichée) et prévient quand Fractus attend ton accord — avec **Autoriser / Refuser / Toujours**
  directement dans la notification. Il redémarre avec le téléphone.
- **Mise à jour de l'appli** : l'appli regarde la dernière Release GitHub, télécharge l'APK et ouvre
  l'installateur Android. Pour que la mise à jour s'installe par-dessus, l'APK doit être signé avec la même clé
  à chaque fois : la CI utilise les secrets `ANDROID_KEYSTORE_B64` et `ANDROID_KEYSTORE_PASSWORD` (voir
  `mobile/tool/sign_release.py`) ; sans eux, c'est une clé de debug différente à chaque compilation.

Sur le téléphone, c'est **la même île que sur le PC**, en plein écran : Fractus animé (tape-le trois fois…),
les mêmes cartes (permission avec Refuser / Autoriser / Toujours et l'aperçu de ce qu'il veut faire, question,
session en cours avec ses étapes en direct), le chat, le journal avec Annuler, l'écran du PC (onglet écran,
pince pour zoomer) et les réglages du PC. Une demande du PC passe devant toute seule.

Le serveur « téléphone » (`lib/services/remote_server.dart`) n'écoute que si l'option est active, exige le code
à chaque requête, et consigne les actions rapides dans le journal. Le code source de l'appli est dans `mobile/`
(Flutter ; le squelette Android est généré par `flutter create` sur la CI). L'interface de l'île — le personnage
(`lib/companion/`), la géométrie, la palette et les briques (`lib/core/`, `lib/island/widgets.dart`) — n'existe
qu'une fois, côté PC : `mobile/tool/sync_shared.sh` (ou `.ps1`) la copie dans `mobile/lib/` avant de compiler.

## Installer (Windows)

Téléchargez **`Fractus-Setup-x.y.z.exe`** dans les [Releases](https://github.com/leoblanchart92-hub/Fractus/releases)
et lancez-le : installation par utilisateur (`%LOCALAPPDATA%\Programs\Fractus`), sans droits
administrateur, raccourci dans le menu Démarrer. Il y a aussi un zip portable (`Fractus-Windows.zip`).

Chaque push est compilé par GitHub Actions (`.github/workflows/windows.yml`) ; les fichiers sont dans
l'onglet *Actions → run → Artifacts*. Un tag `vX.Y.Z` (égal au `version:` de `pubspec.yaml`) publie une
Release avec l'installateur, que les Fractus déjà installés proposeront d'installer.

## La clé API Groq (chat)

1. Créez une clé gratuite sur [console.groq.com/keys](https://console.groq.com/keys) (`gsk_…`).
2. Ouvrez l'île → ⚙️ **Réglages** → **Chat (Groq)** → collez la clé → **Tester** (liste les modèles
   du compte et affiche celui qui sera utilisé) → **Enregistrer**.
3. Facultatif : fixez un modèle précis (menu « Modèles ») ou activez **Recherche web et exécution de
   code** (`groq/compound`).

La clé est écrite dans `%APPDATA%\fractus\settings.json` (champ `chatApiKey`) et ne part que vers
`api.groq.com`, quand vous envoyez un message. Vous pouvez aussi éditer ce fichier à la main :

```json
{ "chatApiKey": "gsk_xxxxxxxx", "chatModel": "", "chatWebSearch": false }
```

Ce que l'agent peut faire pendant le chat :

| Outil | Permission ? |
|---|---|
| `get_sessions`, `read_file`, `list_directory`, `search_text`, `get_datetime`, `system_info`, `list_processes`, `list_windows`, `notify` | non (lecture / anodin) |
| `write_file`, `edit_file` | carte **Autoriser / Refuser / Toujours** |
| `run_command` (PowerShell, dans le dossier de travail) | carte, « Toujours » par première commande (`git`, `npm`…) |
| `fetch_url` | carte |
| `open`, `focus_window`, `window_action`, `send_keys`, `kill_process`, `clipboard_get`, `clipboard_set`, `screenshot`, `set_volume`, `power` | carte « Fractus veut agir sur ton PC », « Toujours » par type d'action |
| `look_at_screen` (capture + modèle vision Llama 4 : description et coordonnées des éléments), `click`, `move_mouse`, `scroll`, `drag` | carte, « Toujours » par type d'action (`get_mouse_position` : libre) |
| `remember`, `forget` (mémoire longue `memoire.md`) | carte « Retenir : … » / « Oublier : … » |

Le dossier de travail se règle dans Réglages → Chat (vide = projet de l'agent en avant, sinon votre
profil). Fractus n'approuve jamais une permission d'un autre agent : ça reste un clic humain.

Tout vit dans `%APPDATA%\fractus\` : `settings.json`, `conversations\*.json` (les 60 dernières),
`memoire.md`, `journal.json` et `backups\` (les copies d'avant, effacées avec le journal).

## Construire et lancer (Windows)

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop) ≥ 3.22 avec le
support desktop Windows, Visual Studio 2022 avec la charge « Développement Desktop en C++ ».

```powershell
git clone https://github.com/leoblanchart92-hub/Fractus.git
cd Fractus
flutter pub get
flutter run -d windows        # pour développer
flutter build windows --release   # l'exécutable : build\windows\x64\runner\Release\fractus.exe
```

Au premier lancement, Fractus sort de l'île et fait coucou. Ouvrez l'île (bord haut de l'écran, puis
clic) → **Demander à Fractus**, et parlez-lui : « ouvre Spotify », « range mes téléchargements par type »,
« crée un script qui… », « combien de RAM il me reste ? ».

## Brancher Claude Code

Voir [`hook/README.md`](hook/README.md) : un script PowerShell relaie les hooks de Claude Code vers
`http://127.0.0.1:7788/hook`, et `hook/claude-settings.example.json` donne le bloc `hooks` à fusionner
dans `%USERPROFILE%\.claude\settings.json`.

## Où sont les choses

| Dossier | Contenu |
|---|---|
| `lib/core/` | géométrie de l'île (`layout.dart`), palette (`theme.dart`), modèles, état, réglages |
| `lib/companion/` | `bot_engine.dart` (le personnage et son moteur d'animation), `companion_view.dart` (ticker + CustomPaint) |
| `lib/island/` | l'île (`island_widget.dart`), sa logique (`controller.dart`), les briques (`widgets.dart`) et les vues |
| `lib/services/` | fenêtre transparente, icône de notification, lancement auto, mises à jour, serveur de hooks, serveur téléphone, chat + outils de l'agent, mémoire, journal, sons |
| `mobile/` | l'appli Android (Flutter) : état, permissions, chat, écran, actions rapides, widgets |
| `installer/` | le script Inno Setup de `Fractus-Setup-x.y.z.exe` |
| `hook/` | le relais PowerShell pour Claude Code et l'exemple de `settings.json` |
| `windows/` | le runner natif Flutter (CMake, Win32) |

Dépendances : `window_manager`, `screen_retriever`, `flutter_acrylic` (fenêtre sans bordure,
transparente, hors barre des tâches, curseur global), `tray_manager`, `launch_at_startup`,
`package_info_plus`, `http`, `path_provider`.

## Différences avec Coucou

Fractus reprend l'**interface** de Coucou (pas le personnage Mochi, remplacé par le cristal Fractus),
pas son écosystème : pas d'iPhone/Android, pas
d'intégrations Stripe/GitHub/Vercel, pas de dictée, pas de garde-robe, pas de Spotify. Les sons ne
sont pas inclus (voir `lib/services/sound.dart` pour brancher les vôtres).

## Licence

Le code de Coucou est sous licence MIT (© Louis Raillé) et a servi de référence pour ce portage ;
le code de Fractus est lui aussi sous licence MIT. **Attention** : d'après
[LICENSE-ASSETS.md](https://github.com/Louis-CFM/coucou/blob/main/LICENSE-ASSETS.md) de Coucou, les
noms « Coucou » et « Mochi », le personnage Mochi (son design et ses expressions), l'icône et les sons
restent la propriété de Louis Raillé et ne peuvent pas être distribués dans une autre application
sans son accord. Pour un usage personnel, construire et lancer Fractus chez vous ne pose pas de
problème ; pour **publier** Fractus, donnez-lui son propre personnage, son propre nom de personnage et
ses propres sons, ou demandez-lui la permission (raillelouis@gmail.com).
