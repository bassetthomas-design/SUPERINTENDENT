<# 
  tools\add-emotion-engine.ps1
  Ajoute un moteur d’émotions + petites phrases + détection d’activité à Virgil.UI.
  Idempotent (ré-exécutable). Compatible .NET 8 / WPF.

  Ce script :
   - crée/alimente Assets\phrases.json
   - référence le JSON dans Virgil.UI.csproj (CopyToOutputDirectory=PreserveNewest)
   - ajoute ViewModels\EmotionEngine.cs, ViewModels\ActivityDetector.cs
   - ajoute Services\EmotionRuntime.cs (bootstrap App)
   - crée ou patch App.xaml.cs pour démarrer EmotionRuntime au lancement

  Utilisation :
    pwsh -ExecutionPolicy Bypass -File .\tools\add-emotion-engine.ps1 -Verbose
#>

[CmdletBinding()]
param(
  [string]$CsprojPath = "src\Virgil.UI\Virgil.UI.csproj",
  [string]$PhrasesRel = "Assets\phrases.json"
)

$ErrorActionPreference = "Stop"

function Write-Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg){ Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "! $msg" -ForegroundColor Yellow }
function Write-Fail($msg){ Write-Host "✖ $msg" -ForegroundColor Red }

# -- 0) Préliminaires
if(-not (Test-Path $CsprojPath)){ throw "Projet introuvable: $CsprojPath (lance depuis la racine du repo)" }
$uiDir = Split-Path $CsprojPath -Parent

# -- 1) Créer phrases.json si absent
$phrasesPath = Join-Path $uiDir $PhrasesRel
$phrasesDir  = Split-Path $phrasesPath -Parent
if(-not (Test-Path $phrasesDir)){ New-Item -ItemType Directory -Force -Path $phrasesDir | Out-Null }

if(-not (Test-Path $phrasesPath)){
@'
{
  "idle": [
    "Je garde un œil sur le système… tout est fluide.",
    "Rien à signaler. Je reste en veille émotionnelle.",
    "Vérif rapide: mémoire OK, CPU calme."
  ],
  "jokes": [
    "Pourquoi Windows aime la pluie ? Il gère bien les fenêtres.",
    "Je n’ai pas de bug, juste des fonctionnalités surprises."
  ],
  "tips": [
    "Astuce: Win+Shift+S pour une capture instantanée.",
    "Pense à vider %TEMP% de temps en temps."
  ],
  "gaming": [
    "Mode Gaming: je rafraîchis les capteurs plus souvent.",
    "Bon frag ! Je baisse les notifs pendant la partie."
  ],
  "browsing": [
    "Navigation détectée, je filtre quelques pop-ups système.",
    "Si tu veux je peux prendre une note à la volée."
  ],
  "working": [
    "Focus mode: je limite les distractions.",
    "Je peux lancer une sauvegarde Git si tu veux."
  ]
}
'@ | Set-Content -Encoding UTF8 -Path $phrasesPath
  Write-Ok "$PhrasesRel créé"
} else {
  Write-Info "$PhrasesRel déjà présent (ok)"
}

# -- 2) Charger csproj + NamespaceManager
[xml]$xml = Get-Content -Raw $CsprojPath
$nsUri = $xml.DocumentElement.NamespaceURI
if([string]::IsNullOrWhiteSpace($nsUri)){ $nsUri = "http://schemas.microsoft.com/developer/msbuild/2003" }
$nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$nsmgr.AddNamespace("ns",$nsUri)

# -- 3) Ajouter <Content Include="Assets\phrases.json"> CopyToOutputDirectory=PreserveNewest
$xpath = "//Content[@Include='$PhrasesRel']"
$existingContent = $xml.SelectSingleNode($xpath,$nsmgr)

if(-not $existingContent){
  $ig = $xml.SelectSingleNode("//ItemGroup[ns:Content or ns:None or ns:Compile or ns:Page]", $nsmgr)
  if(-not $ig){
    $ig = $xml.CreateElement("ItemGroup",$nsUri)
    [void]$xml.Project.AppendChild($ig)
  }

  $content = $xml.CreateElement("Content",$nsUri)
  $content.SetAttribute("Include",$PhrasesRel)
  $copy = $xml.CreateElement("CopyToOutputDirectory",$nsUri)
  $copy.InnerText = "PreserveNewest"
  [void]$content.AppendChild($copy)
  [void]$ig.AppendChild($content)
  $xml.Save($CsprojPath)
  Write-Ok "Référencé $PhrasesRel (CopyToOutputDirectory=PreserveNewest)"
} else {
  $copy = $existingContent.SelectSingleNode("CopyToOutputDirectory",$nsmgr)
  if(-not $copy){ 
    $copy = $xml.CreateElement("CopyToOutputDirectory",$nsUri)
    $copy.InnerText = "PreserveNewest"
    [void]$existingContent.AppendChild($copy)
    $xml.Save($CsprojPath)
    Write-Ok "Ajout CopyToOutputDirectory=PreserveNewest"
  } elseif($copy.InnerText -ne "PreserveNewest") {
    $copy.InnerText = "PreserveNewest"
    $xml.Save($CsprojPath)
    Write-Ok "Normalisé CopyToOutputDirectory=PreserveNewest"
  } else {
    Write-Info "Content $PhrasesRel déjà OK"
  }
}

# -- 4) Ajouter fichiers C#
$vmDir = Join-Path $uiDir "ViewModels"
$svcDir = Join-Path $uiDir "Services"
New-Item -ItemType Directory -Force -Path $vmDir | Out-Null
New-Item -ItemType Directory -Force -Path $svcDir | Out-Null

$emotionEnginePath = Join-Path $vmDir "EmotionEngine.cs"
$activityPath      = Join-Path $vmDir "ActivityDetector.cs"
$runtimePath       = Join-Path $svcDir "EmotionRuntime.cs"

if(-not (Test-Path $emotionEnginePath)){
@'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Windows.Threading;

namespace Virgil.UI.ViewModels
{
    public class EmotionEngine
    {
        private readonly DispatcherTimer _timer;
        private readonly Random _rng = new Random();
        private Dictionary<string, string[]> _phrases = new();

        /// <summary>
        /// Fired when the engine decides to speak.
        /// args: (category, phrase)
        /// </summary>
        public event Action<string, string>? OnSpeak;

        /// <summary>
        /// Min/Max in minutes between spontaneous speeches.
        /// </summary>
        public int MinMinutes { get; set; } = 1;
        public int MaxMinutes { get; set; } = 10;

        public EmotionEngine()
        {
            _timer = new DispatcherTimer(DispatcherPriority.Background);
            _timer.Tick += (_, __) => MaybeSpeak();
            ReloadPhrases();
            ResetNextInterval();
        }

        public void Start() => _timer.Start();
        public void Stop()  => _timer.Stop();

        public void ReloadPhrases()
        {
            try
            {
                string baseDir = AppContext.BaseDirectory;
                string jsonPath = Path.Combine(baseDir, "Assets", "phrases.json");
                if (!File.Exists(jsonPath))
                {
                    // fallback: dev run from project folder
                    string fallback = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "phrases.json");
                    if (File.Exists(fallback)) jsonPath = fallback;
                }

                var json = File.ReadAllText(jsonPath);
                var doc = JsonSerializer.Deserialize<Dictionary<string, string[]>>(json, new JsonSerializerOptions{
                    PropertyNameCaseInsensitive = true
                });
                if (doc != null) _phrases = doc;
            }
            catch { /* keep last phrases */ }
        }

        public string GetRandom(string category, string fallback = "…")
        {
            if (_phrases.TryGetValue(category, out var arr) && arr.Length > 0)
            {
                return arr[_rng.Next(arr.Length)];
            }
            return fallback;
        }

        private void MaybeSpeak()
        {
            // Pick a random category depending on nothing for now (idle/jokes/tips)
            string[] cats = new[] { "idle", "jokes", "tips" };
            string cat = cats[_rng.Next(cats.Length)];
            string line = GetRandom(cat);
            OnSpeak?.Invoke(cat, line);

            ResetNextInterval();
        }

        private void ResetNextInterval()
        {
            int minutes = _rng.Next(Math.Max(1, MinMinutes), Math.Max(MinMinutes+1, MaxMinutes+1));
            _timer.Interval = TimeSpan.FromMinutes(minutes);
        }
    }
}
'@ | Set-Content -Encoding UTF8 -Path $emotionEnginePath
  Write-Ok "EmotionEngine.cs créé"
} else {
  Write-Info "EmotionEngine.cs déjà présent"
}

if(-not (Test-Path $activityPath)){
@'
using System;
using System.Diagnostics;
using System.Linq;

namespace Virgil.UI.ViewModels
{
    public enum ActivityKind { Idle, Gaming, Browsing, Working }

    public class ActivityDetector
    {
        private readonly string[] _gameHints = new[] { "steam", "bf", "dota", "cs2", "eldenring", "fortnite", "leagueclient", "wow" };
        private readonly string[] _browser  = new[] { "chrome", "msedge", "opera", "firefox", "brave" };
        private readonly string[] _dev      = new[] { "devenv", "rider64", "code", "dotnet", "msbuild", "powershell", "pwsh" };

        public ActivityKind Detect()
        {
            try
            {
                var procs = Process.GetProcesses();
                var names = procs.Select(p => {
                    try { return p.ProcessName.ToLowerInvariant(); } catch { return ""; }
                });

                if (names.Any(n => _gameHints.Any(g => n.Contains(g))))
                    return ActivityKind.Gaming;

                if (names.Any(n => _browser.Contains(n)))
                    return ActivityKind.Browsing;

                if (names.Any(n => _dev.Contains(n)))
                    return ActivityKind.Working;

                return ActivityKind.Idle;
            }
            catch { return ActivityKind.Idle; }
        }
    }
}
'@ | Set-Content -Encoding UTF8 -Path $activityPath
  Write-Ok "ActivityDetector.cs créé"
} else {
  Write-Info "ActivityDetector.cs déjà présent"
}

if(-not (Test-Path $runtimePath)){
@'
using System;
using System.Windows;
using System.Windows.Threading;
using Virgil.UI.ViewModels;

namespace Virgil.UI.Services
{
    /// <summary>
    /// Point d’entrée unique pour démarrer EmotionEngine + ActivityDetector.
    /// Non-invasif: pas de dépendance directe à la MainWindow ou VM existantes.
    /// </summary>
    public static class EmotionRuntime
    {
        public static EmotionEngine Engine { get; private set; } = new EmotionEngine();
        public static ActivityDetector Detector { get; private set; } = new ActivityDetector();

        private static DispatcherTimer _probe = new DispatcherTimer(DispatcherPriority.Background);

        public static void Init()
        {
            // Abonnement aux “speaks”
            Engine.OnSpeak += (cat, line) =>
            {
                // Simple: toast console. Tu peux relayer vers ta VM/Chat via un event aggregator plus tard.
                System.Diagnostics.Debug.WriteLine($"[Virgil] {cat}: {line}");
            };

            // Sondage activité toutes les 15s
            _probe.Interval = TimeSpan.FromSeconds(15);
            _probe.Tick += (_, __) => ProbeActivity();
            _probe.Start();

            Engine.Start();
        }

        private static ActivityKind _last = ActivityKind.Idle;

        private static void ProbeActivity()
        {
            var k = Detector.Detect();
            if (k != _last)
            {
                _last = k;
                switch (k)
                {
                    case ActivityKind.Gaming:
                        Engine.MinMinutes = 3;
                        Engine.MaxMinutes = 8;
                        break;
                    case ActivityKind.Browsing:
                        Engine.MinMinutes = 2;
                        Engine.MaxMinutes = 6;
                        break;
                    case ActivityKind.Working:
                        Engine.MinMinutes = 4;
                        Engine.MaxMinutes = 10;
                        break;
                    default:
                        Engine.MinMinutes = 1;
                        Engine.MaxMinutes = 10;
                        break;
                }
                System.Diagnostics.Debug.WriteLine($"[Virgil] Activity={k} (cadence={Engine.MinMinutes}-{Engine.MaxMinutes} min)");
            }
        }
    }
}
'@ | Set-Content -Encoding UTF8 -Path $runtimePath
  Write-Ok "EmotionRuntime.cs créé"
} else {
  Write-Info "EmotionRuntime.cs déjà présent"
}

# -- 5) S’assurer que ces .cs sont compilés (si EnableDefaultCompileItems=false)
$needsCompileInclude = $false
$enableDefault = $xml.SelectSingleNode("//PropertyGroup/ns:EnableDefaultCompileItems",$nsmgr)
if($enableDefault -and ($enableDefault.InnerText -eq "false")){
  $needsCompileInclude = $true
}

if($needsCompileInclude){
  $compileIg = $xml.SelectSingleNode("//ItemGroup[ns:Compile]", $nsmgr)
  if(-not $compileIg){
    $compileIg = $xml.CreateElement("ItemGroup",$nsUri)
    [void]$xml.Project.AppendChild($compileIg)
  }

  foreach($rel in @("ViewModels\EmotionEngine.cs","ViewModels\ActivityDetector.cs","Services\EmotionRuntime.cs")){
    $xp = "//Compile[@Include='$rel']"
    if(-not $xml.SelectSingleNode($xp,$nsmgr)){
      $node = $xml.CreateElement("Compile",$nsUri)
      $node.SetAttribute("Include",$rel)
      [void]$compileIg.AppendChild($node)
      Write-Ok "Ajout Compile Include=`"$rel`""
    } else {
      Write-Info "Compile Include=`"$rel`" déjà présent"
    }
  }
  $xml.Save($CsprojPath)
} else {
  Write-Info "EnableDefaultCompileItems=true (les .cs seront pris automatiquement)"
}

# -- 6) Créer/Patcher App.xaml.cs pour démarrer EmotionRuntime
$appXaml = Join-Path $uiDir "App.xaml"
$appCs   = Join-Path $uiDir "App.xaml.cs"

if(-not (Test-Path $appXaml)){
@'
<Application x:Class="Virgil.UI.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             StartupUri="MainWindow.xaml">
</Application>
'@ | Set-Content -Encoding UTF8 -Path $appXaml
  Write-Ok "App.xaml créé (basique)"
}

if(-not (Test-Path $appCs)){
@'
using System.Windows;
using Virgil.UI.Services;

namespace Virgil.UI
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            EmotionRuntime.Init();
        }
    }
}
'@ | Set-Content -Encoding UTF8 -Path $appCs
  Write-Ok "App.xaml.cs créé avec démarrage EmotionRuntime"
} else {
  # Patch idempotent : ajouter using + Init() si absents
  $txt = Get-Content -Raw $appCs
  $changed = $false
  if($txt -notmatch "using\s+Virgil\.UI\.Services;"){
    $txt = "using Virgil.UI.Services;`r`n" + $txt
    $changed = $true
  }
  if($txt -notmatch "EmotionRuntime\.Init\(\);"){
    # Injecter dans OnStartup si présent, sinon créer OnStartup
    if($txt -match "protected\s+override\s+void\s+OnStartup\s*\(\s*StartupEventArgs\s+\w+\s*\)"){
      $txt = [regex]::Replace($txt, "(protected\s+override\s+void\s+OnStartup\s*\(\s*StartupEventArgs\s+\w+\s*\)\s*\{\s*base\.OnStartup\(.*?\);\s*)", '$1 EmotionRuntime.Init(); ', 'Singleline')
    } else {
      # Ajouter un OnStartup complet dans la classe App
      $txt = [regex]::Replace($txt,
        "(public\s+partial\s+class\s+App\s*:\s*Application\s*\{)",
        "`$1`r`n        protected override void OnStartup(StartupEventArgs e){ base.OnStartup(e); EmotionRuntime.Init(); }",
        'Singleline')
    }
    $changed = $true
  }
  if($changed){ Set-Content -Encoding UTF8 -Path $appCs -Value $txt; Write-Ok "App.xaml.cs patché (EmotionRuntime.Init())" }
  else { Write-Info "App.xaml.cs déjà OK" }
}

Write-Host ""
Write-Ok "Moteur d’émotions installé."
Write-Host "➡ Lance un build : dotnet build `"$CsprojPath`" -c Release" -ForegroundColor DarkGray
Write-Host "➡ Au runtime : le moteur parle aléatoirement (1-10 min) et ajuste sa cadence selon l’activité." -ForegroundColor DarkGray

