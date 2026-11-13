# Version Windows de sync_shared.sh : copie l'interface partagée depuis ..\lib.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
foreach ($f in @("core\anim.dart","core\layout.dart","core\theme.dart","core\models.dart","companion\bot_engine.dart","companion\companion_view.dart","island\widgets.dart")) {
  New-Item -ItemType Directory -Force (Split-Path (Join-Path "lib" $f)) | Out-Null
  Copy-Item (Join-Path "..\lib" $f) (Join-Path "lib" $f) -Force
}
"Interface partagée copiée depuis ..\lib"
