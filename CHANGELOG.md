# Nouveautés de Fractus

Ce fichier est lu par l'application (PC et téléphone) pour la page « Nouveautés »,
et sert de notes de version sur GitHub. Une section par version, la plus récente en haut :
`## <version> · <date>`, puis des puces. Le gras, le code et les listes sont rendus.

## 0.12.0 · 16 novembre 2026

- **Le cerveau de Fractus tourne sur ton PC** : plus besoin de clé Groq. Réglages → Chat → « Sur ce PC (Ollama) ». Fractus **installe Ollama** lui-même (bouton *Installer Ollama*), le lance, et **télécharge le modèle** (`lfm3:1.7b` par défaut, modifiable) avec une barre de progression.
- Rien ne part sur Internet, pas de quota. Pour une question difficile, le moteur **Dans le cloud (Groq)** reste à un clic, avec ta clé.
- Les fichiers images sont décrits par un modèle vision d'Ollama s'il y en a un d'installé (ex. `qwen2.5vl:3b`).
- Le téléphone affiche le moteur en cours et son état dans Réglages → Chat.

## 0.11.4 · 16 novembre 2026

- **Nouveautés** : cette page, sur le PC (icône 🎁 dans l'en-tête de l'île, et Réglages → Version) et sur le téléphone (Réglages → Nouveautés). Elle s'ouvre toute seule après une mise à jour, le temps de voir ce qui a changé.
- Les notes de version sur GitHub viennent du même fichier.

## 0.11.3 · 16 novembre 2026

- **Chat mis en forme** sur PC et téléphone : titres, listes, citations, **gras**, *italique*, `code`, et des blocs de code propres avec un bouton **Copier**.
- « Fractus écrit… » : trois points qui respirent ; l'outil en cours s'affiche en italique à côté.
- L'heure sous le dernier message de chaque série ; sur PC, **Copier** apparaît au survol d'une bulle.
- Champ multiligne : sur PC, **Entrée envoie, Maj+Entrée va à la ligne**.

## 0.11.2 · 16 novembre 2026

- Un **trombone** dans le champ du chat ouvre la boîte « Ouvrir » de Windows pour joindre des fichiers sans glisser.
- Un fichier glissé réveille l'île même repliée : toute la bande haute de l'écran compte.

## 0.11.1 · 15 novembre 2026

- **Glisser des fichiers sur l'île** : Fractus fait de grands yeux, sautille, puis les attrape avec des étoiles.
- Il **lit** le texte et le code, **décrit** les images, **liste** les dossiers, et connaît le chemin des autres fichiers pour les ouvrir avec ses outils.
- Les fichiers joints apparaissent en pastilles dans la conversation (PC et téléphone).

## 0.11.0 · 15 novembre 2026

- **Parler à Fractus** : un micro dans le champ du chat du téléphone (dictée Android, rien ne part chez nous).
- **Journal de connexion** sur le PC et le téléphone (Détails → Copier), pour comprendre pourquoi ça ne se connecte pas.
- Des tests automatiques en CI sur les pièces critiques (code d'appairage, rendez-vous, adresses).

## 0.10.8 · 15 novembre 2026

- Le PC vérifie lui-même que son annonce et son tunnel sont joignables depuis Internet : ligne d'état vraie, bouton **Vérifier**, relance automatique.
- Téléphone : message précis quand aucune adresse ne répond.

## 0.10.7 · 15 novembre 2026

- **Juste un code**, des deux côtés : le PC affiche son code en gros et une ligne d'état en clair ; le téléphone a un grand champ code. Plus aucune adresse « https » à voir ou à taper (les détails techniques restent repliés).

## 0.10.6 · 15 novembre 2026

- Téléphone : bouton **Diagnostic** (Internet, annonce du PC, chaque adresse, code).

## 0.10.5 · 15 novembre 2026

- **Connexion facile** : le téléphone n'a besoin que du code ; le PC dépose ses adresses à un point de rendez-vous chiffré.
- Tunnel Internet toujours actif avec le serveur. **Tailscale retiré**.

## 0.10.4 · 15 novembre 2026

- Accès depuis Internet sans Tailscale ni Wi-Fi commun : tunnel Cloudflare lancé par le PC, adresse retrouvée par le téléphone via un point de rendez-vous chiffré.
- Les mauvais codes sont ralentis.

## 0.10.3 · 15 novembre 2026

- Accès à distance via Tailscale (adresses multiples, pare-feu, installation guidée).
- Téléphone : boutons plus grands, glissement entre onglets, vibrations, légende réseau, champ « Demande à Fractus », indicateur de frappe, copie par appui long.

## 0.10.0 · 14 novembre 2026

- Téléphone : **notifications Autoriser / Refuser** (service natif), appairage par **QR code**, mise à jour de l'APK depuis l'appli.
- L'icône de Fractus comme icône d'application Android.

## 0.9.0 · 13 novembre 2026

- Téléphone : **la même île que sur le PC** (Fractus animé, cartes, chat, journal, réglages), en plein écran, au-dessus de l'écran du PC.

## 0.8.0 · 13 novembre 2026

- Téléphone = miroir du PC : fil d'activité en direct, journal + Annuler, historique des conversations, mémoire éditable, réglages du PC.

## 0.7.0 · 13 novembre 2026

- Serveur de contrôle sur le PC (état, permissions, chat, écran, actions rapides, code d'appairage) et **appli Android Fractus** avec deux widgets d'écran d'accueil.

## 0.6.0 · 13 novembre 2026

- **Mémoire** : conversations persistantes (historique, nouvelle conversation), mémoire longue `memoire.md` (retenir / oublier), journal d'activité avec copies d'avant et **Annuler**.

## 0.5.0 · 13 novembre 2026

- **Vision** (regarder l'écran avec une grille de coordonnées), souris (clic, déplacement, défilement, glisser), fenêtres (actions, positions).

## 0.4.0 · 13 novembre 2026

- Un seul Fractus : outils PC (ouvrir, fenêtres, clavier, processus, presse-papiers, capture, volume, alimentation) **sous permission**.
- Quotas Groq : attente du délai annoncé, bascule automatique vers un autre modèle.

## 0.3.0 · 13 novembre 2026

- Fractus devient un **agent** (écrire, modifier, lancer, consulter) sous permission ; thème **Aurora**.

## 0.2.0 · 13 novembre 2026

- Chat Groq : modèle le plus puissant choisi automatiquement, raisonnement poussé, réponses en streaming, outils locaux en lecture seule.
- Le compagnon **Fractus** (un petit cristal aux grands yeux), icône de notification, lancement automatique, mises à jour, installateur.

## 0.1.0 · 13 novembre 2026

- Première version : l'île en haut de l'écran Windows, les pastilles d'agents, les cartes de permission, le chat.
