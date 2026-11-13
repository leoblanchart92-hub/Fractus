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
- 🤖 **Fractus est lui-même un agent de code** — comme Claude Code, avec votre clé **Groq** (gratuite) :
  le modèle le plus capable du compte choisi automatiquement (gpt-oss-120b, Kimi K2, Llama 3.3 70B…),
  raisonnement au maximum, réponses en streaming, et des outils sur votre machine : il **lit, cherche,
  écrit, modifie des fichiers, lance des commandes PowerShell et consulte des URL**. Chaque action
  passe par la carte **Autoriser / Refuser / Toujours** de l'île ; son travail apparaît comme une
  session « Fractus » avec ses étapes. En option, `groq/compound` ajoute la recherche web côté Groq.
- 🌌 **Thème Aurora** — noir bleuté profond, surfaces teintées, accent cyan → violet en dégradé sur les
  boutons et en lueur diffuse derrière les cartes.
- ⚙️ **Réglages dans l'île** — survol, son, lancement avec Windows, port des hooks, clé API, mises à jour, démo, quitter.
- 🫥 **En arrière-plan** — pas de fenêtre dans la barre des tâches : une icône dans la zone de
  notification (clic gauche : ouvrir l'île ; clic droit : réglages, mises à jour, quitter) et, par
  défaut, un lancement automatique avec Windows (désactivable dans les réglages).
- 🔄 **Mises à jour** — Fractus regarde les Releases GitHub au lancement puis toutes les 6 h ; quand
  une nouvelle version existe, l'île s'ouvre sur une carte **Installer / Plus tard**. L'installateur
  se télécharge, se lance en silencieux, remplace les fichiers et relance Fractus.
- 🔒 **Privé** — aucune télémétrie, aucun compte. Le serveur de hooks n'écoute que sur `127.0.0.1` ;
  la seule requête sortante hors chat est le contrôle de version sur `api.github.com`.

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
| `get_sessions`, `read_file`, `list_directory`, `search_text`, `get_datetime` | non (lecture) |
| `write_file`, `edit_file` | carte **Autoriser / Refuser / Toujours** |
| `run_command` (PowerShell, dans le dossier de travail) | carte, « Toujours » par première commande (`git`, `npm`…) |
| `fetch_url` | carte |

Le dossier de travail se règle dans Réglages → Chat (vide = projet de l'agent en avant, sinon votre
profil). Fractus n'approuve jamais une permission d'un autre agent : ça reste un clic humain.

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

Au premier lancement, Fractus sort de l'île et fait coucou. Comme aucune session ne tourne encore,
ouvrez l'île (bord haut de l'écran, puis clic) : **Jouer la démo** rejoue le scénario des captures de
Coucou (Korus, SBE Hub, Morning Brief, Publication IG) avec une permission, une question et une fin.

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
| `lib/services/` | fenêtre transparente, icône de notification, lancement auto, mises à jour, serveur de hooks, démo, chat, sons |
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
