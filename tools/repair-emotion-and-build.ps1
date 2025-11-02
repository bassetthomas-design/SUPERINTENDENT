# C:\Dev\VirgilOps\tools\repair-emotion-and-build.ps1
[CmdletBinding()]
param()

function Get-RepoRoot {
  $cur = (Get-Location).Path
  if ($MyInvocation.MyCommand.Path) {
    $cur = Split-Path -Parent $MyInvocation.MyCommand.Path
    $cur = Split-Path -Parent $cur
  }
  for($i=0;$i -lt 8;$i++){
    if(Test-Path (Join-Path $cur 'src\Virgil.UI\Virgil.UI.csproj')){ return $cur }
    $cur = Split-Path -Parent $cur
  }
  throw "Racine repo introuvable (src\Virgil.UI\Virgil.UI.csproj)."
}

function EnsureTimersQualification($path){
  if(-not (Test-Path $path)){ return }
  $t = Get-Content -Raw $path

  # 1) injecte 'using System.Timers;' juste après le bloc de usings
  if($t -notmatch '\busing\s+System\.Timers;'){
    $pattern = '(\A(?:using\s+[^\r\n]+;\s*)+)'
    $replacement = '$1' + "using System.Timers;" + [Environment]::NewLine
    $t = [regex]::Replace($t,$pattern,$replacement,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  }

  # 2) qualifie Timer & ElapsedEventArgs
  $t = $t -replace '(?<![\w\.])Timer(?![\w])','System.Timers.Timer'
  $t = $t -replace '(?<![\w\.])ElapsedEventArgs(?![\w])','System.Timers.ElapsedEventArgs'

  Set-Content -Path $path -Encoding UTF8 -Value $t
}

$root   = Get-RepoRoot
$uiProj = Join-Path $root 'src\Virgil.UI\Virgil.UI.csproj'
$uiDir  = Split-Path -Parent $uiProj
$vm     = Join-Path $uiDir 'ViewModels\MainViewModel.cs'
$runtime= Join-Path $uiDir 'Services\EmotionRuntime.cs'
$appxcs = Join-Path $uiDir 'App.xaml.cs'
$phr    = Join-Path $uiDir 'Assets\phrases.json'

Write-Host "🔧 Racine: $root" -ForegroundColor Cyan

# --- 1) Réécrit complètement EmotionRuntime.cs (contenu sûr) ---
$runtimeContent = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Timers;

namespace Virgil.UI.Services
{
    public static class EmotionRuntime
    {
        private static readonly Random _rng = new Random();
        private static readonly List<string> _phrases = new List<string>();
        private static System.Timers.Timer? _timer;
        private static bool _enabled;

        public static bool IsEnabled => _enabled;

        public static void Init(string baseDir)
        {
            try
            {
                var phrasesPath = Path.Combine(baseDir, "Assets", "phrases.json");
                if (File.Exists(phrasesPath))
                {
                    var json = File.ReadAllText(phrasesPath);
                    var list = JsonSerializer.Deserialize<List<string>>(json);
                    if (list != null)
                    {
                        _phrases.Clear();
                        _phrases.AddRange(list);
                    }
                }
            }
            catch
            {
                // ignore
            }

            EnsureTimer();
        }

        public static void SetEnabled(bool enabled)
        {
            _enabled = enabled;
            EnsureTimer();
        }

        public static void ForceSpeakOnce()
        {
            if (_phrases.Count == 0) return;
            var idx = _rng.Next(_phrases.Count);
            var text = _phrases[idx];
            // TODO: brancher vers la UI (bulle / chat)
            System.Diagnostics.Debug.WriteLine($"[Virgil] {text}");
        }

        private static void EnsureTimer()
        {
            if (_timer == null)
            {
                _timer = new System.Timers.Timer();
                _timer.AutoReset = false;
                _timer.Elapsed += OnTick;
            }

            if (_enabled)
            {
                _timer.Interval = NextDelayMs();
                _timer.Start();
            }
            else
            {
                _timer.Stop();
            }
        }

        private static void OnTick(object? s, System.Timers.ElapsedEventArgs e)
        {
            try
            {
                if (_enabled) ForceSpeakOnce();
            }
            finally
            {
                if (_enabled && _timer != null)
                {
                    _timer.Interval = NextDelayMs();
                    _timer.Start();
                }
            }
        }

        private static double NextDelayMs()
        {
            // 1 à 10 minutes
            var minutes = _rng.Next(1, 11);
            return TimeSpan.FromMinutes(minutes).TotalMilliseconds;
        }
    }
}
"@
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtime) | Out-Null
Set-Content -Path $runtime -Encoding UTF8 -Value $runtimeContent
Write-Host "✅ EmotionRuntime.cs réécrit" -ForegroundColor Green

# --- 2) Sécurise MainViewModel.cs (Timer & ElapsedEventArgs qualifiés) ---
EnsureTimersQualification $vm
Write-Host "✅ MainViewModel.cs corrigé (System.Timers.*)" -ForegroundColor Green

# --- 3) App.xaml.cs → Init si manquant ---
if(Test-Path $appxcs){
  $ax = Get-Content -Raw $appxcs
  if($ax -notmatch 'using\s+Virgil\.UI\.Services;'){
    $pattern = '(\A(?:using\s+[^\r\n]+;\s*)+)'
    $replacement = '$1' + "using Virgil.UI.Services;" + [Environment]::NewLine
    $ax = [regex]::Replace($ax,$pattern,$replacement,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  }
  if($ax -notmatch 'EmotionRuntime\.Init\('){
    $ax = $ax -replace '(InitializeComponent\(\);\s*)', '$1 EmotionRuntime.Init(AppContext.BaseDirectory); '
  }
  Set-Content -Path $appxcs -Encoding UTF8 -Value $ax
  Write-Host "✅ App.xaml.cs : Init() OK" -ForegroundColor Green
}

# --- 4) phrases.json de secours ---
if(-not (Test-Path $phr)){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $phr) | Out-Null
@"
[
  "Analyse système nominale.",
  "Je veille. 👀",
  "Astuce: un petit `winget upgrade --all` fait des miracles.",
  "Pense à t’hydrater !",
  "Tout roule côté températures."
]
"@ | Set-Content -Path $phr -Encoding UTF8
  Write-Host "✅ phrases.json créé" -ForegroundColor Green
}

# --- 5) Build ---
Write-Host "`n🧪 Build..." -ForegroundColor Cyan
dotnet build $uiProj -c Release
if($LASTEXITCODE -ne 0){ throw "Build échoué" }

Write-Host "`n🎉 OK. Lance l’app :" -ForegroundColor Green
Write-Host "   dotnet run --project `"$uiProj`" -c Release" -ForegroundColor Yellow
Write-Host "`nRappels :" -ForegroundColor Cyan
Write-Host " - Bouton Surveillance : ON/OFF du moteur (SetEnabled)." -ForegroundColor Gray
Write-Host " - Bouton Dire une phrase : déclenche immédiatement ForceSpeakOnce()." -ForegroundColor Gray
Write-Host " - Phrases aléatoires : toutes les 1–10 minutes quand Surveillance = ON." -ForegroundColor Gray
