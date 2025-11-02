param(
  [string]$Root = "C:\Dev\VirgilOps",
  [string]$Sln  = "Virgil"
)

function W($path,$content){
  New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
  $content | Out-File -FilePath $path -Encoding UTF8 -Force
}

Set-Location $Root

# --------- 1) Chemins projets ----------
$projCore  = ".\src\$Sln.Core\$Sln.Core.csproj"
$projAgent = ".\src\$Sln.Agent\$Sln.Agent.csproj"
$projUI    = ".\src\$Sln.UI\$Sln.UI.csproj"

# --------- 2) Paquets nécessaires (au cas où) ----------
dotnet add $projAgent package LibreHardwareMonitorLib  | Out-Null

# --------- 3) Impl capteurs côté Agent ----------
$agentImpl = @'
using Microsoft.Extensions.Hosting;
using Serilog;
using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Virgil.Core;
using LibreHardwareMonitor.Hardware;

public sealed class AgentWorker : BackgroundService
{
    private readonly ISensors _sensors;
    public AgentWorker(ISensors sensors){ _sensors = sensors; }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        Log.Information("Agent online (sensors active)");
        var ipcDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil", "ipc");
        Directory.CreateDirectory(ipcDir);
        var ipcFile = Path.Combine(ipcDir, "latest.json");

        while(!ct.IsCancellationRequested)
        {
            var snap = _sensors.ReadOnce();
            try
            {
                var json = JsonSerializer.Serialize(snap, new JsonSerializerOptions{ WriteIndented = false });
                File.WriteAllText(ipcFile, json);
            }
            catch (Exception ex) { Log.Error(ex, "Write IPC failed"); }
            await Task.Delay(1000, ct);
        }
    }
}

public sealed class SensorManager : ISensors, IDisposable
{
    private readonly Computer _pc;
    public SensorManager()
    {
        _pc = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMemoryEnabled = true,
            IsStorageEnabled = true,
            IsMotherboardEnabled = true
        };
        _pc.Open();
    }

    public MetricsSnapshot ReadOnce()
    {
        float cpuLoad = 0f, gpuLoad = 0f, gpuTemp = 0f, ramPct = 0f, diskFreePct = 0f;
        string topProc = "explorer.exe";
        DateTime at = DateTime.UtcNow;

        foreach (var hw in _pc.Hardware)
        {
            hw.Update();
            foreach (var s in hw.Sensors)
            {
                try
                {
                    if (s.SensorType == SensorType.Load && s.Name.Contains("CPU Total", StringComparison.OrdinalIgnoreCase))
                        cpuLoad = s.Value.GetValueOrDefault(cpuLoad);

                    if (s.SensorType == SensorType.Temperature && s.Name.Contains("GPU Core", StringComparison.OrdinalIgnoreCase))
                        gpuTemp = s.Value.GetValueOrDefault(gpuTemp);

                    if (s.SensorType == SensorType.Load && s.Name.Contains("GPU Core", StringComparison.OrdinalIgnoreCase))
                        gpuLoad = s.Value.GetValueOrDefault(gpuLoad);

                    if (s.SensorType == SensorType.Load && (s.Name.Contains("Memory", StringComparison.OrdinalIgnoreCase) || s.Name.Equals("RAM", StringComparison.OrdinalIgnoreCase)))
                        ramPct = s.Value.GetValueOrDefault(ramPct);
                }
                catch { /* ignore sensor read errors */ }
            }
        }

        // Disk free % simple: drive C:
        try
        {
            var di = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory)!);
            if (di.TotalSize > 0) diskFreePct = (float)(100.0 * di.TotalFreeSpace / di.TotalSize);
        } catch { }

        return new MetricsSnapshot(
            CpuPct: cpuLoad,
            GpuPct: gpuLoad,
            GpuTempC: gpuTemp,
            RamPct: ramPct,
            DiskFreePct: diskFreePct,
            TopProcess: topProc,
            AtUtc: at
        );
    }

    public void Dispose()
    {
        try { _pc.Close(); } catch { }
        _pc.Dispose();
    }
}

public sealed class CleanerManager : ICleaner
{
    public Task<CleanupReport> RunAsync(CleanupRequest req, CancellationToken ct)
        => Task.FromResult(new CleanupReport(1234, 456_789_000, new[]{"windows_temp","browsers"}, Array.Empty<string>()));
}

public sealed class UpdaterManager : IUpdater
{
    public Task<UpdateReport> RunAsync(UpdateRequest req, CancellationToken ct)
        => Task.FromResult(new UpdateReport(17, 1_234_567_890, new[]{"winget","windows_update","defender_full"}, Array.Empty<string>()));
}
'@
W ".\src\$Sln.Agent\WorkerAndManagers.cs" $agentImpl

# --------- 4) UI : timer qui lit le dernier snapshot et rafraîchit l'écran ----------
$uiApp = @'
using System.Windows;
using Virgil.Core;

namespace Virgil.UI
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            LogBoot.Init();
            base.OnStartup(e);
        }
    }
}
'@
W ".\src\$Sln.UI\App.xaml.cs" $uiApp

$uiXaml = @'
<Window x:Class="Virgil.UI.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Virgil — SURINTENDENT" Height="720" Width="1180">
  <Grid Background="{StaticResource Bg}">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="360"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Margin="16" Background="{StaticResource Panel}" CornerRadius="16">
      <StackPanel Margin="16">
        <TextBlock Text="Avatar (mock)" Foreground="{StaticResource Accent}" FontSize="28" Margin="0,0,0,16"/>
        <StackPanel>
          <TextBlock Text="CPU %" Foreground="White"/>
          <ProgressBar x:Name="CpuBar" Height="14" Minimum="0" Maximum="100"/>
          <TextBlock Text="GPU % / °C" Foreground="White" Margin="0,8,0,0"/>
          <StackPanel Orientation="Horizontal" Spacing="8">
            <ProgressBar x:Name="GpuBar" Height="14" Width="200" Minimum="0" Maximum="100"/>
            <TextBlock x:Name="GpuTemp" Foreground="White"/>
          </StackPanel>
          <TextBlock Text="RAM %" Foreground="White" Margin="0,8,0,0"/>
          <ProgressBar x:Name="RamBar" Height="14" Minimum="0" Maximum="100"/>
          <TextBlock Text="Disk Free %" Foreground="White" Margin="0,8,0,0"/>
          <ProgressBar x:Name="DiskBar" Height="14" Minimum="0" Maximum="100"/>
          <TextBlock Text="Top Process" Foreground="White" Margin="0,8,0,0"/>
          <TextBlock x:Name="TopProc" Foreground="White"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <Border Grid.Column="1" Margin="8,16,16,16" Background="{StaticResource Panel}" CornerRadius="16">
      <ScrollViewer Margin="16">
        <StackPanel>
          <TextBlock Text="Bulles (mock)" Foreground="White"/>
        </StackPanel>
      </ScrollViewer>
    </Border>
  </Grid>
</Window>
'@
W ".\src\$Sln.UI\MainWindow.xaml" $uiXaml

$uiCs = @'
using System;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using Virgil.Core;

namespace Virgil.UI
{
    public partial class MainWindow : Window
    {
        private readonly string _ipcFile;
        private readonly DispatcherTimer _timer;

        public MainWindow()
        {
            InitializeComponent();
            _ipcFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil", "ipc", "latest.json");
            _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _timer.Tick += (s,e) => RefreshMetrics();
            _timer.Start();
        }

        private void RefreshMetrics()
        {
            try
            {
                if (!File.Exists(_ipcFile)) return;
                var json = File.ReadAllText(_ipcFile);
                var snap = JsonSerializer.Deserialize<MetricsSnapshot>(json);
                if (snap == null) return;

                CpuBar.Value  = snap.CpuPct;
                GpuBar.Value  = snap.GpuPct;
                RamBar.Value  = snap.RamPct;
                DiskBar.Value = snap.DiskFreePct;
                GpuTemp.Text  = $"{snap.GpuTempC:0}°C";
                TopProc.Text  = snap.TopProcess ?? "n/a";
            }
            catch { /* ignore UI read errors */ }
        }
    }
}
'@
W ".\src\$Sln.UI\MainWindow.xaml.cs" $uiCs

# --------- 5) Build & run hints ----------
dotnet build -c Release
Write-Host "`n✅ Capteurs intégrés. " -ForegroundColor Green
Write-Host "Lance l'Agent (en debug via 'dotnet run' pour voir les logs dans la console) :" -ForegroundColor Cyan
Write-Host "dotnet run --project .\src\$Sln.Agent\$Sln.Agent.csproj`n"
Write-Host "Puis lance l'UI :" -ForegroundColor Cyan
Write-Host "& .\src\$Sln.UI\bin\Release\net8.0-windows\$Sln.UI.exe`n"
