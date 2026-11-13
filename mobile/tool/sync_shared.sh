#!/usr/bin/env sh
# Copie dans l'appli téléphone les fichiers d'interface partagés avec le Fractus
# du PC (le personnage, la géométrie de l'île, la palette, les briques des vues).
# Lancé par la CI avant la compilation ; à lancer aussi en local avant `flutter run`.
set -e
cd "$(dirname "$0")/.."
mkdir -p lib/core lib/companion lib/island
for f in core/anim.dart core/layout.dart core/theme.dart core/models.dart companion/bot_engine.dart companion/companion_view.dart island/widgets.dart; do
  cp "../lib/$f" "lib/$f"
done
echo "Interface partagée copiée depuis ../lib"
