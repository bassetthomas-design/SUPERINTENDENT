# tools\ui-tweaks.ps1
# (version simplifiée qui marche sans magie de chemin)

$ErrorActionPreference = 'Stop'

# Dossier racine du projet (à adapter si besoin)
$root = "C:\Dev\VirgilOps"
Set-Location $root

function Patch-Text {
  param([string]$Path,[scriptblock]$Edit)
  if(-not (Test-Path $Path)){ Write-Error "Fichier introuvable: $Path" }
  $txt = Get-Content -Raw $Path -Encoding UTF8
  $orig = $txt
  $txt = & $Edit $txt
  if($txt -ne $orig){
    Set-Content -Path $Path -Value $txt -Encoding UTF8
    Write-Host "✓ patched $Path" -ForegroundColor Green
  } else {
    Write-Host "• aucun changement $Path"
  }
}

# 1) Boutons plus gros
$styles = "$root\src\Virgil.UI\Styles\Controls.xaml"
Patch-Text -Path $styles -Edit {
  param($t)
  if($t -notmatch 'BigButtonStyle'){
    $inject = @'
  <Style x:Key="BigButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="FontSize" Value="16"/>
    <Setter Property="Padding" Value="16,8"/>
    <Setter Property="MinHeight" Value="36"/>
    <Setter Property="Margin" Value="8,0,0,0"/>
  </Style>
  <Style TargetType="Button" BasedOn="{StaticResource BigButtonStyle}"/>
'@
    $t = $t -replace '(</ResourceDictionary>)', "$inject`r`n`$1"
  }
  return $t
}

# 2) Bouton Surveillance dans ActionBar
$actionBar = "$root\src\Virgil.UI\Controls\ActionBar.xaml"
Patch-Text -Path $actionBar -Edit {
  param($t)
  $t = $t -replace '<Button ', '<Button FontSize="16" Padding="16,8" MinHeight="36" '
  if($t -notmatch 'IsChatterEnabled'){
    $toggle = @'
  <ToggleButton Content="Surveillance"
                IsChecked="{Binding IsChatterEnabled, Mode=TwoWay}"
                Margin="8,0,0,0" MinHeight="36" Padding="16,8"/>
'@
    $t = $t -replace '(</StackPanel>\s*</UserControl>)', "$toggle`r`n`$1"
  }
  return $t
}

# 3) Propriété IsChatterEnabled dans MainViewModel
$vmPath = "$root\src\Virgil.UI\ViewModels\MainViewModel.cs"
Patch-Text -Path $vmPath -Edit {
  param($t)
  if($t -notmatch 'IsChatterEnabled'){
    $prop = @'
        private bool _isChatterEnabled = true;
        public bool IsChatterEnabled
        {
            get => _isChatterEnabled;
            set
            {
                if (_isChatterEnabled == value) return;
                _isChatterEnabled = value;
                OnPropertyChanged();
                Services.EmotionRuntime.SetEnabled(value);
            }
        }
'@
    $t = $t -replace '(public\s+class\s+MainViewModel\s*:\s*INotifyPropertyChanged\s*\{)', '$1' + "`r`n" + $prop
  }
  return $t
}

# 4) Supprimer la bouche
$avatar = "$root\src\Virgil.UI\Controls\VirgilAvatar.xaml"
if(Test-Path $avatar){
  $ax = Get-Content -Raw $avatar
  $ax2 = ($ax -split "`r?`n") | Where-Object {$_ -notmatch 'Mouth|Smile|Bezier'} | Out-String
  if($ax2 -ne $ax){
    Set-Content -Path $avatar -Value $ax2 -Encoding UTF8
    Write-Host "✓ bouche supprimée dans VirgilAvatar.xaml" -ForegroundColor Green
  }
}

# 5) Rebuild
Write-Host "🧪 Build..." -ForegroundColor Cyan
dotnet build "$root\src\Virgil.UI\Virgil.UI.csproj" -c Release
Write-Host "✅ Terminé — relance l’appli !" -ForegroundColor Green
