#!/usr/bin/env sh
# Copie dans l'appli téléphone les fichiers d'interface partagés avec le Fractus
# du PC (le personnage, la géométrie de l'île, la palette, les briques des vues).
# Lancé par la CI avant la compilation ; à lancer aussi en local avant `flutter run`.
set -e
cd "$(dirname "$0")/.."
mkdir -p lib/core lib/companion lib/island
for f in core/anim.dart core/layout.dart core/theme.dart core/models.dart core/rendezvous.dart core/markdown.dart core/changelog.dart companion/bot_engine.dart companion/companion_view.dart island/widgets.dart island/rich_text.dart island/news_list.dart; do
  cp "../lib/$f" "lib/$f"
done
mkdir -p assets
cp ../CHANGELOG.md assets/CHANGELOG.md
echo "Interface partagée copiée depuis ../lib"
