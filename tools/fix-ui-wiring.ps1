# C:\Dev\VirgilOps\tools\fix-ui-wiring.ps1
[CmdletBinding()]
param()

# ---------- utilitaires ----------
function Resolve-RepoRoot {
  # 1) si exécuté comme fichier
  if ($MyInvocation.MyCommand.Path) {
    return (Split-Path -Parent $MyInvocation.MyCommand.Path) | Split-Path -Parent
  }
  # 2) sinon on remonte jusqu'à trouver Virgil.UI.csproj
  $cur = (Get-Location).Path
  for ($i=0; $i -lt 8; $i++) {
    if (Test-Path (Join-Path $cur 'src\Virgil.UI\Virgil.UI.csproj')) { return $cur }
    $cur = Split-Path -Parent $cur
  }
  throw "Impossible de localiser la racine du repo (src\Virgil.UI\Virgil.UI.csproj introuvable)."
}

function Replace-InFile($path,[string]$pattern,[string]$replacement,[switch]$Multiline,[switch]$CaseSensitive){
  if(-not (Test-Path $path)){ return $false }
  $content = Get-Content -Raw $path -ErrorAction Stop
  $opts = 'None'
  if(-not $CaseSensitive){ $opts = 'IgnoreCase' }
  if($Multiline){ $opts = "$opts, Multiline" }
  $regex = New-Object System.Text.RegularExpressions.Regex($pattern, $opts)
  $new = $regex.Replace($content,$replacement)
  if($new -ne $content){
    Set-Content -Path $path -Value $new -Encoding UTF8
    return $true
  }
  return $false
}

function Ensure-UsingTimers($path){
  if(-not (Test-Path $path)){ return }
  $t = Get-Content -Raw $path
  if($t -notmatch '\busing\s+System\.Timers;'){
    $t = $t -replace '(^using\s+[^\r\n]+;\s*)+(?s)', '$0using System.Timers;' + [Environment]::NewLine
  }
  # qualifie Timer/ElapsedEventArgs pour éviter l’ambiguïté
  $t = $t -replace '(?<![\w\.])Timer(?![\w])','System.Timers.Timer'
  $t = $t -replace '(?<![\w\.])ElapsedEventArgs(?![\w])','System.Timers.ElapsedEventArgs'
  Set-Content -Path $path -Value $t -Encoding UTF8
}

# ---------- chemins ----------
$root   = Resolve-RepoRoot
$uiProj = Join-Path $root 'src\Virgil.UI\Virgil.UI.csproj'
$uiDir  = Split-Path -Parent $uiProj
$vm     = Join-Path $uiDir 'ViewModels\MainViewModel.cs'
$relay  = Join-Path $uiDir 'ViewModels\RelayCommand.cs'
$mwXaml = Join-Path $uiDir 'MainWindow.xaml'
$mwCs   = Join-Path $uiDir 'MainWindow.xaml.cs'
$avatar = Join-Path $uiDir 'Controls\VirgilAvatar.xaml'
$runtime= Join-Path $uiDir 'Services\EmotionRuntime.cs'
$appxcs = Join-Path $uiDir 'App.xaml.cs'
$phr    = Join-Path $uiDir 'Assets\phrases.json'

Write-Host "🔧 Racine: $root" -ForegroundColor Cyan

# ---------- 1) Avatar: supprimer/masquer la bouche ----------
if(Test-Path $avatar){
  # masque tout élément nommé 'Mouth' (quelle que soit la balise)
  [void](Replace-InFile $avatar '(<[^>]+x:Name="Mouth"[^>]*>)' '<!-- $1 -->' -Multiline)
  [void](Replace-InFile $avatar '(</[^>]+x:Name="Mouth"[^>]*>)' '<!-- $1 -->' -Multiline)
  # et s'il y a une propriété Visibility explicite
  [void](Replace-InFile $avatar 'x:Name="Mouth"([^>]+)Visibility="Visible"' 'x:Name="Mouth"$1Visibility="Collapsed"' -Multiline)
  Write-Host "✅ Avatar: bouche désactivée" -ForegroundColor Green
} else {
  Write-Host "ℹ️  Avatar introuvable (skip) : $avatar" -ForegroundColor Yellow
}

# ---------- 2) MainWindow.xaml : lier les boutons ----------
if(Test-Path $mwXaml){
  # Surveillance ON/OFF
  [void](Replace-InFile $mwXaml 'x:Name="BtnSurveillance"([^>]+)Command="\{[^}]+\}"' 'x:Name="BtnSurveillance"$1Command="{Binding ToggleMonitorCommand}"' -Multiline)
  [void](Replace-InFile $mwXaml 'x:Name="BtnSurveillance"([^>]+)(?=>)' 'x:Name="BtnSurveillance"$1 Command="{Binding ToggleMonitorCommand}"' -Multiline)
  # Dire une phrase
  [void](Replace-InFile $mwXaml 'x:Name="BtnSay"([^>]+)Command="\{[^}]+\}"' 'x:Name="BtnSay"$1Command="{Binding SayRandomCommand}"' -Multiline)
  [void](Replace-InFile $mwXaml 'x:Name="BtnSay"([^>]+)(?=>)' 'x:Name="BtnSay"$1 Command="{Binding SayRandomCommand}"' -Multiline)
  Write-Host "✅ MainWindow.xaml: commandes liées" -ForegroundColor Green
}

# ---------- 3) MainWindow.xaml.cs : DataContext ----------
if(Test-Path $mwCs){
  $t = Get-Content -Raw $mwCs
  if($t -notmatch 'this\.DataContext\s*=\s*new\s+MainViewModel\('){
    $t = $t -replace '(public\s+partial\s+class\s+MainWindow\s*:\s*Window\s*\{\s*public\s+MainWindow\(\)\s*\{\s*InitializeComponent\(\);\s*)',
                    '$1 this.DataContext = new MainViewModel(); '
    Set-Content -Path $mwCs -Value $t -Encoding UTF8
    Write-Host "✅ MainWindow.xaml.cs: DataContext=MainViewModel" -ForegroundColor Green
  } else {
    Write-Host "ℹ️  DataContext déjà présent" -ForegroundColor Yellow
  }
}

# ---------- 4) ViewModel: commandes + prop MonitoringEnabled ----------
if(Test-Path $relay){
  # s’assure que RelayCommand existe
  # (rien à faire, on suppose ok)
}

if(Test-Path $vm){
@"
using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Timers;
using Virgil.UI.Services;

namespace Virgil.UI.ViewModels
{
    public partial class MainViewModel : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;
        void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

        private bool _monitoringEnabled;
        public bool MonitoringEnabled
        {
            get => _monitoringEnabled;
            set
            {
                if (_monitoringEnabled != value)
                {
                    _monitoringEnabled = value;
                    EmotionRuntime.SetEnabled(_monitoringEnabled);
                    OnPropertyChanged();
                }
            }
        }

        public RelayCommand ToggleMonitorCommand { get; }
        public RelayCommand SayRandomCommand { get; }

        public MainViewModel()
        {
            ToggleMonitorCommand = new RelayCommand(_ => MonitoringEnabled = !MonitoringEnabled);
            SayRandomCommand = new RelayCommand(_ => EmotionRuntime.ForceSpeakOnce());
        }
    }
}
"@ | Set-Content -Path $vm -Encoding UTF8
  Write-Host "✅ MainViewModel.cs réécrit (ToggleMonitor + SayRandom + MonitoringEnabled)" -ForegroundColor Green
}

# ---------- 5) EmotionRuntime : API minimale requise ----------
if(Test-Path $runtime){
  $rt = Get-Content -Raw $runtime
} else {
  $rt = ''
}

if($rt -notmatch 'class\s+EmotionRuntime'){
@"
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
        private static Timer? _timer;
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
                    if (list != null) { _phrases.Clear(); _phrases.AddRange(list); }
                }
            }
            catch { /* ignore */ }

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
            // TODO: brancher avec ChatPane / bulles / logs UI
            System.Diagnostics.Debug.WriteLine($"[Virgil] {text}");
        }

        private static void EnsureTimer()
        {
            if (_timer == null)
            {
                _timer = new System.Timers.Timer();
                _timer.Elapsed += OnTick;
            }
            _timer.AutoReset = false;
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

        private static void OnTick(object? s, ElapsedEventArgs e)
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
            // 1 à 10 minutes, aléatoire
            var minutes = _rng.Next(1, 11);
            return TimeSpan.FromMinutes(minutes).TotalMilliseconds;
        }
    }
}
"@ | Set-Content -Path $runtime -Encoding UTF8
  Write-Host "✅ EmotionRuntime.cs créé (SetEnabled/ForceSpeakOnce/timer)" -ForegroundColor Green
} else {
  # s’assure des usings & Timer qualifié
  Ensure-UsingTimers $runtime
  if($rt -notmatch 'SetEnabled\('){
    $rt += @"

public static void SetEnabled(bool enabled)
{
    _enabled = enabled;
    EnsureTimer();
}
"@
  }
  if($rt -notmatch 'ForceSpeakOnce\('){
    $rt += @"

public static void ForceSpeakOnce()
{
    if (_phrases.Count == 0) return;
    var idx = new Random().Next(_phrases.Count);
    var text = _phrases[idx];
    System.Diagnostics.Debug.WriteLine($""[Virgil] {text}"");
}
"@
  }
  Set-Content -Path $runtime -Value $rt -Encoding UTF8
  Write-Host "✅ EmotionRuntime.cs complété" -ForegroundColor Green
}

# ---------- 6) App.xaml.cs : init du runtime + chemin phrases ----------
if(Test-Path $appxcs){
  $ax = Get-Content -Raw $appxcs
  if($ax -notmatch 'EmotionRuntime\.Init\('){
    $ax = $ax -replace '(InitializeComponent\(\);\s*)', '$1 Virgil.UI.Services.EmotionRuntime.Init(AppContext.BaseDirectory); '
    if($ax -notmatch 'using\s+Virgil\.UI\.Services;'){
      $ax = $ax -replace '(^using\s+[^\r\n]+;\s*)+(?s)', '$0using Virgil.UI.Services;' + [Environment]::NewLine
    }
    Set-Content -Path $appxcs -Value $ax -Encoding UTF8
    Write-Host "✅ App.xaml.cs: EmotionRuntime.Init() ajouté" -ForegroundColor Green
  } else {
    Write-Host "ℹ️  App.xaml.cs: Init déjà présent" -ForegroundColor Yellow
  }
}

# ---------- 7) phrases.json par défaut ----------
if(-not (Test-Path $phr)){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $phr) | Out-Null
@"
[
  "Analyse des circuits… c’est propre !",
  "Un café ? Pour toi, toujours.",
  "Températures nominales, tout roule.",
  "Rappelle-toi : sauvegarder, c’est aimer le futur toi.",
  "Je surveille… 👀"
]
"@ | Set-Content -Path $phr -Encoding UTF8
  Write-Host "✅ phrases.json créé (base)" -ForegroundColor Green
}

# ---------- 8) Copier phrases.json à la sortie ----------
# Ajoute l’item Conditionnel (SDK style, sans xmlns)
[xml]$projXml = Get-Content -Raw $uiProj
$ig = $projXml.Project.ItemGroup | Where-Object { $_.Content } | Select-Object -First 1
if(-not $ig){
  $ig = $projXml.CreateElement('ItemGroup')
  [void]$projXml.Project.AppendChild($ig)
}
$exists = $projXml.SelectSingleNode("//Content[@Include='Assets\phrases.json']")
if(-not $exists){
  $c = $projXml.CreateElement('Content')
  $c.SetAttribute('Include','Assets\phrases.json')
  $ct = $projXml.CreateElement('CopyToOutputDirectory')
  $ct.InnerText = 'PreserveNewest'
  [void]$c.AppendChild($ct)
  [void]$ig.AppendChild($c)
  $projXml.Save($uiProj)
  Write-Host "✅ Virgil.UI.csproj: Assets\\phrases.json -> CopyToOutputDirectory" -ForegroundColor Green
}

# ---------- 9) Qualifie Timer & ElapsedEventArgs dans le VM ----------
Ensure-UsingTimers $vm

# ---------- 10) Build ----------
Write-Host "`n🧪 Build..." -ForegroundColor Cyan
dotnet build $uiProj -c Release
if($LASTEXITCODE -ne 0){ throw "Build échoué" }

Write-Host "`n🎉 OK. Lance l’app :" -ForegroundColor Green
Write-Host "   dotnet run --project `"$uiProj`" -c Release" -ForegroundColor Yellow
Write-Host "`nUtilisation :" -ForegroundColor Cyan
Write-Host " - Bouton Surveillance : ON/OFF du moteur (timer + phrases)." -ForegroundColor Gray
Write-Host " - Bouton Dire une phrase : déclenche une phrase immédiatement." -ForegroundColor Gray
Write-Host " - Avatar : bouche supprimée, réactions par les yeux." -ForegroundColor Gray
