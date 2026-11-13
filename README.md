<div align="center">

<img src="windows/runner/resources/app_icon.ico" width="96" alt="Icône Fractus">

# Fractus

**Toute la puissance dans une IA.**
Un petit compagnon qui vit en haut de l'écran et garde un œil sur vos agents de code
(Claude Code et les autres) : approuvez, répondez, discutez, sans quitter ce que vous faites.

Application **Windows** écrite en **Flutter**. L'interface reprend celle de
[Coucou](https://github.com/Louis-CFM/coucou) de Louis Raillé (Louis-CFM) : l'île en haut
de l'écran, Mochi, les pastilles, les cartes de permission, de question et de fin, le chat.

</div>

---

## Ce que ça fait

- 🏝️ **L'île** — une île noire collée en haut au centre de l'écran. Cachée quand il ne se passe
  rien, elle sort quand le pointeur touche le bord haut (bande de 240 × 6 px), s'ouvre au clic
  (ou au survol, dans les réglages) et se replie quand le pointeur s'en va. Tailles, rayons,
  courbes d'ouverture (`cubic-bezier(.32,1.22,.42,1)`, 520 ms) et de fermeture (340 ms) sont celles de Coucou.
- 🫧 **Mochi** — le petit squircle aux grands yeux, dessiné en code (aucune image) : respiration,
  clignements, regard qui suit la souris, états `idle / working / thinking / searching / approval /
  question / error / finished / ratelimit / sleeping / dizzy`, badges, particules (étoiles, cœurs,
  sueur, z), le salut de la main au lancement, l'agacement quand on le tape (trois tapes : étourdi),
  les cœurs quand on reste sur lui deux secondes. Portage du `BotEngine` de Coucou.
- 🤖 **Les sessions en direct** — chaque session Claude Code a sa pastille colorée et son mini Mochi ;
  la carte montre le projet, l'agent et les dernières étapes (lecture, modification, commande, recherche).
- ✅ **Permissions et questions** — `PermissionRequest` s'affiche avec **Refuser (N) / Autoriser (Y) /
  Toujours** ; `AskUserQuestion` montre ses choix (jusqu'à 4 questions, sélection multiple).
  Jamais rien d'autorisé sans un clic ; sans réponse, le terminal reprend la main.
- 🎉 **Terminé / erreur** — Mochi fait sa roulade, la carte verte résume la réponse.
- 💬 **Chat** — avec Claude via votre propre clé Anthropic (Réglages → Chat), qui voit vos sessions en cours.
- ⚙️ **Réglages dans l'île** — survol, son, port des hooks, clé API, démo, quitter.
- 🔒 **Privé** — aucune télémétrie, aucun compte. Le serveur de hooks n'écoute que sur `127.0.0.1`.

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

Au premier lancement, Mochi sort de l'île et fait coucou. Comme aucune session ne tourne encore,
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
| `lib/mochi/` | `bot_engine.dart` (le personnage, portage de `BotEngine`), `mochi_view.dart` (ticker + CustomPaint) |
| `lib/island/` | l'île (`island_widget.dart`), sa logique (`controller.dart`), les briques (`widgets.dart`) et les vues |
| `lib/services/` | fenêtre transparente toujours au premier plan, serveur de hooks, démo, chat, sons |
| `hook/` | le relais PowerShell pour Claude Code et l'exemple de `settings.json` |
| `windows/` | le runner natif Flutter (CMake, Win32) |

Dépendances : `window_manager`, `screen_retriever`, `flutter_acrylic` (fenêtre sans bordure,
transparente, hors barre des tâches, curseur global), `http`, `path_provider`.

## Différences avec Coucou

Fractus reprend l'**interface** de Coucou, pas son écosystème : pas d'iPhone/Android, pas
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
