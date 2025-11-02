[CmdletBinding()]
param(
  [string[]] $Projects = @('Virgil.Agent','Virgil.UI'),
  [string]   $Solution = 'VirgilOps.sln',
  [string]   $Configuration = 'Release',
  [string]   $Runtime = 'win-x64',
  [switch]   $NoRelease,
  [switch]   $CreateTag,
  [string]   $Version,
  [switch]   $ContinueOnError
)

# === Utilities ===============================================================
function Header($m){ Write-Host ("`n🔧 {0}" -f $m) -ForegroundColor Cyan }
function Ok($m){ Write-Host ("✅ {0}" -f $m) -ForegroundColor Green }
function Warn($m){ Write-Host ("⚠ {0}" -f $m) -ForegroundColor Yellow }
function Fail($m){ Write-Host ("✖ {0}" -f $m) -ForegroundColor Red; throw $m }

function RunDotnet([string]$args){
  & dotnet $args
  if($LASTEXITCODE -ne 0){ throw ("dotnet {0} failed (exit {1})" -f $args,$LASTEXITCODE) }
}

# Default if not explicitly provided
if(-not $PSBoundParameters.ContainsKey('ContinueOnError')){ $ContinueOnError = $true }

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root    = (Resolve-Path .).Path
$art     = Join-Path $root 'artifacts'
$pubRoot = Join-Path $art  'publish'
$zipRoot = Join-Path $art  'zip'

# Clean basic folders
Header "Nettoyage dossiers artifacts/"
New-Item -ItemType Directory -Force -Path $art,$pubRoot,$zipRoot | Out-Null
Get-ChildItem $pubRoot -Recurse -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue
Get-ChildItem $zipRoot -Recurse -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue

# Try solution restore/build if .sln exists
if(Test-Path (Join-Path $root $Solution)){
  Header "Restore solution"
  try { RunDotnet ("restore `"{0}`"" -f $Solution) } catch { Warn ("Restore solution: {0}" -f $_.Exception.Message) }

  Header "Build solution ({0})" -f $Configuration
  try { RunDotnet ("build `"{0}`" -c {1} -warnaserror- /clp:ErrorsOnly" -f $Solution,$Configuration) }
  catch {
    Warn ("Build solution KO: {0}" -f $_.Exception.Message)
    if(-not $ContinueOnError){ Fail "Arrêt sur erreur build solution" }
  }

  # Optional test if a test project exists
  $hasTests = Get-ChildItem -Recurse -Filter *.csproj | Where-Object { $_.FullName -match '\.Tests\\.*\.csproj$' } | Select-Object -First 1
  if($hasTests){
    Header "Tests"
    try { RunDotnet ("test `"{0}`" -c {1} --no-build --nologo" -f $Solution,$Configuration); Ok "Tests OK" }
    catch {
      Warn ("Tests KO: {0}" -f $_.Exception.Message)
      if(-not $ContinueOnError){ Fail "Arrêt sur erreur tests" }
    }
  }
} else {
  Warn ("Solution introuvable: {0} — on continue en mode par projet." -f $Solution)
}

# Resolve project csproj path by convention or search
function Resolve-Csproj([string]$projectName){
  $byConv = Join-Path $root ("src\{0}\{0}.csproj" -f $projectName)
  if(Test-Path $byConv){ return $byConv }
  $found = Get-ChildItem -Recurse -Filter "$projectName.csproj" | Select-Object -First 1
  if($found){ return $found.FullName }
  return $null
}

# Publish each requested project
foreach($p in $Projects){
  $csproj = Resolve-Csproj $p
  if(-not $csproj){
    if($ContinueOnError){ Warn ("{0}: csproj introuvable — skip" -f $p); continue }
    else { Fail ("{0}: csproj introuvable" -f $p) }
  }

  $name   = [IO.Path]::GetFileNameWithoutExtension($csproj)
  $outDir = Join-Path $pubRoot $name
  $zip    = Join-Path $zipRoot ("{0}-{1}-{2}.zip" -f $name,$Runtime,$Configuration)

  Header ("Publish {0} -> {1} ({2})" -f $name,$Runtime,$Configuration)

  try {
    RunDotnet ("publish `"{0}`" -c {1} -r {2} --self-contained:false -p:PublishSingleFile=false -o `"{3}`"" -f $csproj,$Configuration,$Runtime,$outDir)
    if(-not (Test-Path $outDir)){ throw ("Output non créé: {0}" -f $outDir) }
    Ok ("{0} publié" -f $name)
  } catch {
    if($ContinueOnError){
      Warn ("{0}: publish FAILED ({1}) — skip zip" -f $name, $_.Exception.Message)
      continue
    } else {
      Fail ("{0}: publish FAILED" -f $name)
    }
  }

  # Zip
  Header ("Zip {0}" -f $name)
  try {
    if(Test-Path $zip){ Remove-Item $zip -Force -EA SilentlyContinue }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($outDir, $zip)
    Ok ("Zip créé -> {0}" -f $zip)
  } catch {
    if($ContinueOnError){
      Warn ("{0}: zip FAILED ({1})" -f $name, $_.Exception.Message)
    } else {
      Fail ("{0}: zip FAILED" -f $name)
    }
  }
}

# Optional GitHub release
if(-not $NoRelease){
  Header "Publication GitHub Release"
  # Tag/version
  $tag = if([string]::IsNullOrWhiteSpace($Version)) { (Get-Date).ToString("'v'yyyy.MM.dd-HHmm") } else { $Version }
  if($CreateTag){
    try { git tag $tag; git push origin $tag; Ok ("Tag créé/poussé: {0}" -f $tag) }
    catch { Warn ("Création tag échouée: {0}" -f $_.Exception.Message) }
  }

  $zips = Get-ChildItem $zipRoot -Filter *.zip
  if(-not $zips){ Warn "Aucun zip à publier"; return }

  $gh = Get-Command gh -EA SilentlyContinue
  if($gh){
    try {
      & gh release create $tag ($zips.FullName) -t $tag -n "Automated release $tag"
      if($LASTEXITCODE -ne 0){ throw "gh release create exit $LASTEXITCODE" }
      Ok ("Release publiée via gh: {0}" -f $tag)
    } catch {
      Warn ("gh release FAILED: {0}" -f $_.Exception.Message)
    }
  } else {
    Warn "gh CLI absent — saute la création de release. (Tu peux pousser manuellement les zips)"
  }
} else {
  Warn "NoRelease demandé — skip GitHub release."
}

Ok "Terminé."
