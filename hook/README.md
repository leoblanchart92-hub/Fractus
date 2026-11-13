# Brancher Claude Code sur Fractus

Fractus écoute sur `http://127.0.0.1:7788/hook` (port modifiable dans Réglages → Agents).
Le script `fractus-hook.ps1` lit le JSON que Claude Code donne à ses hooks sur stdin
et le poste à l'île.

## Installation

1. Ouvrez `%USERPROFILE%\.claude\settings.json` (créez-le s'il n'existe pas).
2. Fusionnez-y le contenu de `claude-settings.example.json` en remplaçant
   `C:\chemin\Fractus` par le dossier réel du dépôt. Gardez vos hooks existants.
3. Relancez Claude Code. Mochi suit alors chaque session : prompt, lectures,
   modifications, commandes ; les demandes de permission s'affichent dans l'île
   avec **Refuser / Autoriser / Toujours** ; les `AskUserQuestion` montrent leurs choix.

## Ce que fait le script, et ce qu'il ne fait jamais

- Tous les événements sauf `PermissionRequest` repartent immédiatement (3 s de délai au plus).
- `PermissionRequest` attend votre clic jusqu'à 115 s, puis rend la main.
- **Rien n'est autorisé sans un clic.** Si Fractus est fermé, muet ou en erreur,
  le script sort en silence (code 0) et Claude Code demande dans son terminal,
  comme si Fractus n'était pas installé.
- « Toujours autoriser » est mémorisé par Fractus (outil + première commande),
  jamais écrit dans `settings.json` de Claude Code.

## Un autre agent

Ajoutez `-Agent codex` (ou n'importe quel nom) à la commande : l'agent reçoit sa
propre pastille et son propre mini Mochi. Le format attendu est celui des hooks de
Claude Code (`hook_event_name`, `cwd`, `tool_name`, `tool_input`…).

## Tester sans agent

```powershell
'{"hook_event_name":"UserPromptSubmit","session_id":"t1","cwd":"C:\\dev\\MonProjet","prompt":"Corrige les tests"}' |
  powershell -NoProfile -File .\fractus-hook.ps1
```
