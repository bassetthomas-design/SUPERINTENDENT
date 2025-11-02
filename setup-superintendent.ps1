# setup-superintendent.ps1
$ErrorActionPreference = 'Stop'

function Require-Cmd($name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Outil requis introuvable: $name (ajoute-le au PATH)" }
}

Require-Cmd git
Require-Cmd dotnet

# Dossier racine du projet
$Root = "C:\Dev\VirgilOps"
if (-not (Test-Path $Root)) { throw "Dossier introuvable: $Root" }
Set-Location $Root

# URL du dépôt
$RepoUrl = "https://github.com/bassetthomas-design/SUPERINTENDENT.git"

Write-Host "🔧 Init Git dans $Root" -ForegroundColor Cyan
if (-not (Test-Path ".git")) { git init | Out-Null }

# Force la branche 'main'
git checkout -B main | Out-Null

# Remote origin
$remotes = git remote 2>$null
if ($remotes -and ($remotes -contains "origin")) {
  git remote set-url origin $RepoUrl
} else {
  git remote add origin $RepoUrl
}

# .gitignore
@"
bin/
obj/
artifacts/
TestResults/
.vs/
.vscode/
*.user
*.suo
*.log
*.tmp
*.bak
*.orig
*.nupkg
*.snupkg
publish/
"@ | Out-File -FilePath ".gitignore" -Encoding UTF8 -Force

# README
@"
# SUPERINTENDENT

Assistant Windows (.NET 8) — maintenance, monitoring temps réel, avatar façon Superintendent.

## Build local
```powershell
dotnet restore
dotnet build -c Release
dotnet test  -c Release
