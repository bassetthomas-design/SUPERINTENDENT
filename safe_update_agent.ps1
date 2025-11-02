$ErrorActionPreference = "Stop"
$svc  = "VirgilAgent"
$inst = "C:\Program Files\Virgil\Agent"
$src  = ".\artifacts\agent"
$exe  = Join-Path $inst "Virgil.Agent.exe"

function Wait-Unlocked($path, $timeoutSec = 30) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
    try {
      $fs = [System.IO.File]::Open($path,'Open','ReadWrite','None'); $fs.Close(); return $true
    } catch { Start-Sleep -Milliseconds 250 }
  }
  return $false
}

Write-Host "Arrêt du service $svc..." -ForegroundColor Cyan
sc.exe stop $svc *> $null; Start-Sleep 1
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
if($procs){ $procs | Stop-Process -Force -ErrorAction SilentlyContinue }

if(Test-Path $exe){
  if(-not (Wait-Unlocked $exe 30)){ throw "Toujours verrouillé: $exe" }
}

Write-Host "Copie build -> $inst" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $inst | Out-Null
Copy-Item "$src\*" $inst -Force -Recurse

Write-Host "Redémarrage du service $svc..." -ForegroundColor Cyan
sc.exe start $svc | Out-Null
Write-Host "✅ Mise à jour terminée." -ForegroundColor Green
