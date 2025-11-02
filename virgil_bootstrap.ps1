# ============================
#   Virgil Bootstrap Script
# ============================
param([string]$SolutionName = "Virgil")

function Write-Block { param($path,$content)
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    $content | Out-File -FilePath $path -Encoding UTF8 -Force
}

$root = Get-Location
Write-Host "=== Initialisation $SolutionName ===" -ForegroundColor Cyan

# 1) Crée la solution
if(-not (Test-Path "$SolutionName.sln")){ dotnet new sln -n $SolutionName | Out-Null }

# 2) Projets
dotnet new classlib -n "$SolutionName.Core"  -o "src\$SolutionName.Core"  -f net8.0 | Out-Null
dotnet new worker   -n "$SolutionName.Agent" -o "src\$SolutionName.Agent" -f net8.0 | Out-Null
dotnet new wpf      -n "$SolutionName.UI"    -o "src\$SolutionName.UI"    -f net8.0 | Out-Null
dotnet new console  -n "$SolutionName.CLI"   -o "src\$SolutionName.CLI"   -f net8.0 | Out-Null
dotnet new xunit    -n "$SolutionName.Tests" -o "src\$SolutionName.Tests" -f net8.0 | Out-Null

# 3) Ajustements WPF / Windows
(Get-Content "src\$SolutionName.Agent\$SolutionName.Agent.csproj") `
    -replace '<TargetFramework>.*?</TargetFramework>','<TargetFramework>net8.0-windows</TargetFramework>' |
    Set-Content "src\$SolutionName.Agent\$SolutionName.Agent.csproj" -Encoding UTF8

# 4) Ajoute tout à la solution
dotnet sln add (Get-ChildItem -Recurse -Filter *.csproj | ForEach-Object FullName) | Out-Null

# 5) Références croisées
dotnet add "src\$SolutionName.UI\$SolutionName.UI.csproj"       reference "src\$SolutionName.Core\$SolutionName.Core.csproj" | Out-Null
dotnet add "src\$SolutionName.Agent\$SolutionName.Agent.csproj"  reference "src\$SolutionName.Core\$SolutionName.Core.csproj" | Out-Null
dotnet add "src\$SolutionName.CLI\$SolutionName.CLI.csproj"      reference "src\$SolutionName.Core\$SolutionName.Core.csproj" | Out-Null
dotnet add "src\$SolutionName.Tests\$SolutionName.Tests.csproj"  reference "src\$SolutionName.Core\$SolutionName.Core.csproj" | Out-Null

# 6) NuGet packages
function AddPkg($p,$n){ dotnet add $p package $n | Out-Null }
AddPkg "src\$SolutionName.Core\$SolutionName.Core.csproj"  "Serilog"
AddPkg "src\$SolutionName.Core\$SolutionName.Core.csproj"  "Serilog.Sinks.File"
AddPkg "src\$SolutionName.Core\$SolutionName.Core.csproj"  "Serilog.Sinks.Console"
AddPkg "src\$SolutionName.Core\$SolutionName.Core.csproj"  "CommunityToolkit.Mvvm"
AddPkg "src\$SolutionName.Core\$SolutionName.Core.csproj"  "System.Management"
AddPkg "src\$SolutionName.Agent\$SolutionName.Agent.csproj" "LibreHardwareMonitorLib"
AddPkg "src\$SolutionName.Agent\$SolutionName.Agent.csproj" "Microsoft.Extensions.Hosting.WindowsServices"
AddPkg "src\$SolutionName.UI\$SolutionName.UI.csproj"       "CommunityToolkit.Mvvm"

# 7) Fichiers essentiels
Write-Block "src\$SolutionName.Core\Contracts.cs" @"
namespace Virgil.Core;
public interface ICleaner { System.Threading.Tasks.Task<CleanupReport> RunAsync(CleanupRequest req, System.Threading.CancellationToken ct); }
public interface IUpdater { System.Threading.Tasks.Task<UpdateReport> RunAsync(UpdateRequest req, System.Threading.CancellationToken ct); }
public interface ISensors { MetricsSnapshot ReadOnce(); }
public record CleanupRequest(string Level="complet", string[]? Groups=null, bool Simulation=false);
public record CleanupReport(long Files, long BytesFreed, System.Collections.Generic.IReadOnlyList<string> GroupsDone, System.Collections.Generic.IReadOnlyList<string> Errors);
public record UpdateRequest(string[]? Sources);
public record UpdateReport(int ItemsUpdated, long BytesDownloaded, System.Collections.Generic.IReadOnlyList<string> SourcesDone, System.Collections.Generic.IReadOnlyList<string> Errors);
public record MetricsSnapshot(float CpuPct,float GpuPct,float GpuTempC,float RamPct,float DiskFreePct,string? TopProcess,System.DateTime AtUtc);
"@

Write-Block "src\$SolutionName.Core\LogBoot.cs" @"
using Serilog;
namespace Virgil.Core;
public static class LogBoot {
  public static void Init(){
    var dir = System.IO.Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.CommonApplicationData), "Virgil", "logs");
    System.IO.Directory.CreateDirectory(dir);
    var path = System.IO.Path.Combine(dir, $"{System.DateTime.Now:yyyy-MM-dd}.log");
    Log.Logger = new LoggerConfiguration().MinimumLevel.Debug()
      .WriteTo.File(path, rollingInterval: RollingInterval.Day, retainedFileCountLimit:30)
      .WriteTo.Console().CreateLogger();
    Log.Information("=== Virgil ready ===");
  }
}
"@

Write-Block "src\$SolutionName.Agent\WorkerAndManagers.cs" @'
using Microsoft.Extensions.Hosting; using Serilog; using System; using System.Threading; using System.Threading.Tasks; using Virgil.Core;
public sealed class AgentWorker : BackgroundService {
  private readonly ISensors _sensors;
  public AgentWorker(ISensors sensors){ _sensors = sensors; }
  protected override async Task ExecuteAsync(CancellationToken ct){
    Log.Information("Agent online");
    while(!ct.IsCancellationRequested){ var snap=_sensors.ReadOnce(); await Task.Delay(1500, ct); }
  }
}
public sealed class SensorManager : ISensors {
  public MetricsSnapshot ReadOnce(){
    var r=new Random();
    return new MetricsSnapshot(CpuPct:r.Next(5,90),GpuPct:r.Next(3,80),
      GpuTempC:r.Next(40,88),RamPct:r.Next(20,92),
      DiskFreePct:r.Next(5,80),TopProcess:"explorer.exe",AtUtc:DateTime.UtcNow);
  }
}
public sealed class CleanerManager : ICleaner {
  public Task<CleanupReport> RunAsync(CleanupRequest req, CancellationToken ct)
    => Task.FromResult(new CleanupReport(1234,456_789_000,new[]{"windows_temp","browsers"},Array.Empty<string>()));
}
public sealed class UpdaterManager : IUpdater {
  public Task<UpdateReport> RunAsync(UpdateRequest req, CancellationToken ct)
    => Task.FromResult(new UpdateReport(17,1_234_567_890,new[]{"winget","windows_update","defender_full"},Array.Empty<string>()));
}
'@

Write-Block "src\$SolutionName.UI\App.xaml" @"
<Application x:Class="Virgil.UI.App" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" StartupUri="MainWindow.xaml">
  <Application.Resources>
    <SolidColorBrush x:Key="Bg" Color="#0B0F14"/>
    <SolidColorBrush x:Key="Panel" Color="#121821"/>
    <SolidColorBrush x:Key="Accent" Color="#32E5FF"/>
  </Application.Resources>
</Application>
"@
Write-Block "src\$SolutionName.UI\App.xaml.cs" 'using System.Windows; using Virgil.Core; namespace Virgil.UI { public partial class App : Application { protected override void OnStartup(StartupEventArgs e){ LogBoot.Init(); base.OnStartup(e);} } }'
Write-Block "src\$SolutionName.UI\MainWindow.xaml" @"
<Window x:Class="Virgil.UI.MainWindow" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Virgil — SURINTENDENT" Height="720" Width="1180">
  <Grid Background="{StaticResource Bg}">
    <Grid.ColumnDefinitions><ColumnDefinition Width="360"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Grid.Column="0" Margin="16" Background="{StaticResource Panel}" CornerRadius="16"><Grid><TextBlock Text="Avatar (mock)" Foreground="{StaticResource Accent}" FontSize="28" HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid></Border>
    <Border Grid.Column="1" Margin="8,16,16,16" Background="{StaticResource Panel}" CornerRadius="16"><ScrollViewer Margin="16"><StackPanel><TextBlock Text="Bulles (mock)" Foreground="White"/></StackPanel></ScrollViewer></Border>
  </Grid>
</Window>
"@
Write-Block "src\$SolutionName.UI\MainWindow.xaml.cs" 'namespace Virgil.UI { public partial class MainWindow : System.Windows.Window { public MainWindow(){ InitializeComponent(); } } }'
Write-Block "src\$SolutionName.CLI\Program.cs" 'using Virgil.Core; System.Console.WriteLine("Virgil CLI"); LogBoot.Init(); System.Console.WriteLine("Logger prêt.");'

# 8) Build
dotnet restore
dotnet build -c Release

Write-Host "`n✅ Bootstrap terminé."
Write-Host "👉 Pour lancer l’UI : & '.\\src\\$SolutionName.UI\\bin\\Release\\net8.0-windows\\$SolutionName.UI.exe'"
