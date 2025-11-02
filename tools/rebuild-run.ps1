$ErrorActionPreference = ''Stop''
$root = ''C:\Dev\VirgilOps''
$ui   = Join-Path $root ''src\Virgil.UI''
$csproj = Join-Path $ui ''Virgil.UI.csproj''

Write-Host "🔧 Build Release Virgil.UI..." -ForegroundColor Yellow
dotnet build $csproj -c Release
if($LASTEXITCODE -ne 0){ throw "Build échoué" }

Write-Host "🚀 Lancement Virgil.UI..." -ForegroundColor Green
Start-Process dotnet -ArgumentList @("run","-c","Release","--project",$csproj)
