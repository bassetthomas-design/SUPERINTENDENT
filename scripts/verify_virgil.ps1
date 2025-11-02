param(
  [string]$SolutionRoot = "C:\Dev\VirgilOps",
  [string]$ServiceName  = "VirgilAgent",
  [string]$UiExe        = "C:\Dev\VirgilOps\src\Virgil.UI\bin\Release\net8.0-windows\Virgil.UI.exe"
)
$ErrorActionPreference = "SilentlyContinue"

function Resolve-Dotnet {
  $cmd = (Get-Command dotnet -ErrorAction SilentlyContinue)?.Source
  if (-not $cmd) {
    $candidates = @(
      "$env:ProgramFiles\dotnet\dotnet.exe",
      "$env:ProgramFiles(x86)\dotnet\dotnet.exe",
      "$env:USERPROFILE\.dotnet\dotnet.exe"
    )
    $cmd = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  }
  if (-not $cmd) { throw "dotnet introuvable. Ajoute-le au PATH ou installe le SDK .NET." }
  return $cmd
}

function OK($b,$msg){ if($b){Write-Host "✅ $msg" -ForegroundColor Green}else{Write-Host "❌ $msg" -ForegroundColor Red} }

Write-Host "=== Vérification Virgil ===`n" -ForegroundColor Cyan
# [1/8] Build Release...
Write-Host "[1/8] Build Release..." -ForegroundColor Cyan
$Dotnet = Resolve-Dotnet
Push-Location $SolutionRoot
& $Dotnet build "$SolutionRoot\Virgil.sln" -c Release
$buildOk = $LASTEXITCODE -eq 0
OK $buildOk "Build solution"
Pop-Location

# [2/8] Service Windows
Write-Host "`n[2/8] Service Windows..." -ForegroundColor Cyan
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if($null -eq $svc){ OK $false "Service '$ServiceName' installé" } else { OK $true  "Service '$ServiceName' installé ($($svc.Status))" }

# [3/8] Chemin binaire du service
Write-Host "`n[3/8] Chemin du service..." -ForegroundColor Cyan
$svcInfo = sc.exe qc $ServiceName
$binLine = ($svcInfo | Select-String -Pattern "BINARY_PATH_NAME").ToString()
$binPath = $binLine -replace '.*BINARY_PATH_NAME\s*:\s*', '' -replace '^"|"$',''
if($binPath){ Write-Host "Path: $binPath" } else { Write-Host "Path introuvable (service absent ?)" }

# [4/8] Dossiers ProgramData
Write-Host "`n[4/8] Dossiers ProgramData..." -ForegroundColor Cyan
$base   = "$env:ProgramData\Virgil"
$logDir = Join-Path $base "logs"
$cmdDir = Join-Path $base "ipc\commands"
OK (Test-Path $base)   "ProgramData: $base"
OK (Test-Path $logDir) "Logs:       $logDir"
OK (Test-Path $cmdDir) "IPC:        $cmdDir"

# [5/8] Log du jour
Write-Host "`n[5/8] Log du jour..." -ForegroundColor Cyan
$todayLog = Join-Path $logDir ("{0:yyyy-MM-dd}.log" -f (Get-Date))
if(Test-Path $todayLog){ OK $true "Log du jour trouvé: $todayLog"; Get-Content $todayLog -Tail 5 } else { OK $false "Log du jour introuvable" }

# [6/8] Envoi de 2 commandes IPC (Type/CorrelationId/AtUtc)
Write-Host "`n[6/8] Test commandes Agent (Clean/UpdateAll)..." -ForegroundColor Cyan
function Send-Cmd($type){
  $id=[guid]::NewGuid().ToString("N")
  $obj=[pscustomobject]@{ Type=$type; CorrelationId=$id; AtUtc=(Get-Date).ToUniversalTime() }
  $json=$obj|ConvertTo-Json -Depth 5
  $path=Join-Path $cmdDir "$id.json"
  $json|Out-File $path -Encoding UTF8
  return $id
}
$id1=Send-Cmd "Clean"
$id2=Send-Cmd "UpdateAll"
Write-Host "→ Envoyé ($id1 / $id2)"

# [7/8] Attente résultats (45s max)
Write-Host "`n[7/8] Attente résultats..." -ForegroundColor Cyan
function Wait-Result($id,$sec=45){
  $res = Join-Path $cmdDir "$id.result.json"
  $limit = (Get-Date).AddSeconds($sec)
  while((Get-Date) -lt $limit){
    if(Test-Path $res){ return $res }
    Start-Sleep 2
  }
  return $null
}
$res1=Wait-Result $id1
$res2=Wait-Result $id2
OK ($null -ne $res1) "Résultat CLEAN reçu"
OK ($null -ne $res2) "Résultat UPDATE reçu"
if($res1){ Get-Content $res1 }
if($res2){ Get-Content $res2 }

# [8/8] UI
Write-Host "`n[8/8] UI..." -ForegroundColor Cyan
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$val = (Get-ItemProperty -Path $runKey -Name "VirgilUI" -ErrorAction SilentlyContinue).VirgilUI
if($val){ OK $true "Clé Run\VirgilUI présente"; Write-Host "VirgilUI -> $val" } else { OK $false "Clé Run\VirgilUI absente" }
$proc = Get-Process -Name "Virgil.UI" -ErrorAction SilentlyContinue
OK ($null -ne $proc) "UI en cours d'exécution"

Write-Host "`n=== Fin vérif ==="
