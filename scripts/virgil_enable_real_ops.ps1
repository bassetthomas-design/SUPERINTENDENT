param(
  [string]$Root = "C:\Dev\VirgilOps",
  [string]$AgentProj = ".\src\Virgil.Agent\Virgil.Agent.csproj",
  [string]$OutDir = ".\artifacts\agent",
  [string]$InstallDir = "C:\Program Files\Virgil\Agent",
  [string]$ServiceName = "VirgilAgent"
)

# --- Utilise le dotnet explicite (évite PATH qui saute selon la session)
$Dotnet = "C:\Program Files\dotnet\dotnet.exe"
if (-not (Test-Path $Dotnet)) { throw "dotnet introuvable à '$Dotnet'" }

# --- Build & Publish (Release)
& $Dotnet build $Root -c Release
& $Dotnet publish $AgentProj -c Release -r win-x64 `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true --self-contained:false `
  -o $OutDir

# --- Déploiement dans Program Files
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
# Stoppe le service si présent
sc.exe stop $ServiceName *> $null
Start-Sleep 2
# Vide et copie
Get-ChildItem -Force -Path $InstallDir | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
Copy-Item "$OutDir\*" $InstallDir -Force -Recurse

# --- (Re)crée le service si besoin
sc.exe query $ServiceName *> $null
if ($LASTEXITCODE -ne 0) {
  sc.exe create $ServiceName binPath= "`"$InstallDir\Virgil.Agent.exe`"" start= auto DisplayName= "Virgil Agent" | Out-Null
  sc.exe description $ServiceName "Virgil system assistant (sensors/cleanup/updates)" | Out-Null
}

# --- Démarre le service
sc.exe start $ServiceName | Out-Null

# --- Vérifs rapides
$logDir = "C:\ProgramData\Virgil\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
Start-Sleep 2

Write-Host "✔ Build/Publish OK" -ForegroundColor Green
Write-Host "✔ Service redémarré: $ServiceName" -ForegroundColor Green
Write-Host "Derniers logs:" -ForegroundColor Cyan
$last = Get-ChildItem "$logDir\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($last) { Get-Content $last.FullName -Tail 30 } else { Write-Host "(Pas encore de log écrit)"; }
