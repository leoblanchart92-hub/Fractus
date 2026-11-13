# fractus-hook.ps1 — relaie un hook de Claude Code (ou d'un autre agent) vers
# l'île Fractus, puis rend la main. Pendant du relais `coucou-hook` de Coucou.
#
# Règle unique : rien qui autorise quoi que ce soit n'est imprimé sans un clic
# humain. Si Fractus ne répond pas (fermé, délai, erreur), ce script sort en
# silence avec le code 0 : l'agent demande alors dans son terminal, exactement
# comme si Fractus n'était pas installé. Il ne bloque jamais Claude Code.
#
# Usage (dans ~/.claude/settings.json → "hooks") :
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\chemin\Fractus\hook\fractus-hook.ps1"
# Options :
#   -Agent <nom>   étiquette l'agent (ex. "codex") pour lui donner sa propre pastille
#   -Port <n>      port du serveur de hooks (défaut 7788, ou $env:FRACTUS_PORT)

param(
  [string]$Agent = "",
  [int]$Port = 0
)

$ErrorActionPreference = "SilentlyContinue"
if ($Port -le 0) { if ($env:FRACTUS_PORT) { $Port = [int]$env:FRACTUS_PORT } else { $Port = 7788 } }

# Le JSON du hook arrive sur stdin.
$body = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($body)) { exit 0 }

$event = ""
try { $event = (ConvertFrom-Json $body).hook_event_name } catch { }

$url = "http://127.0.0.1:$Port/hook"
if ($Agent -ne "") { $url += "?agent=" + [Uri]::EscapeDataString($Agent) }

# Seule PermissionRequest attend une réponse (≤ 115 s). Les autres repartent tout de suite.
$timeout = if ($event -eq "PermissionRequest") { 115 } else { 3 }

try {
  $client = New-Object System.Net.Http.HttpClient
  $client.Timeout = [TimeSpan]::FromSeconds($timeout)
  $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, "application/json")
  $res = $client.PostAsync($url, $content).GetAwaiter().GetResult()
  if ($event -eq "PermissionRequest" -and $res.StatusCode -eq 200) {
    $reply = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ($reply -and $reply.Trim().StartsWith("{")) {
      # La décision cliquée dans l'île : Claude Code la lit sur stdout.
      [Console]::Out.Write($reply)
    }
  }
} catch {
  # Fractus absent ou muet : silence, le terminal reprend la main.
}
exit 0
