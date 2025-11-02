param(
  [string]$Root = "C:\Dev\VirgilOps",
  [string]$Sln  = "Virgil"
)

function W($path,$content){
  New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
  $content | Out-File -FilePath $path -Encoding UTF8 -Force
}

Set-Location $Root

$projCore  = ".\src\$Sln.Core\$Sln.Core.csproj"
$projAgent = ".\src\$Sln.Agent\$Sln.Agent.csproj"
$projUI    = ".\src\$Sln.UI\$Sln.UI.csproj"

# --- 0) Modèles de commande côté Core ---
$coreCmd = @'
namespace Virgil.Core;

public enum VirgilCommandType { Clean, UpdateAll }

public record CommandRequest(
    VirgilCommandType Type,
    string? CorrelationId,
    System.DateTime AtUtc
);

public record CommandResult(
    string? CorrelationId,
    bool Success,
    string Message,
    System.DateTime FinishedUtc
);
'@
W ".\src\$Sln.Core\Commands.cs" $coreCmd

# --- 1) Agent : watcher de commandes + exécutions réelles ---
$agentCmd = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Serilog;
using Virgil.Core;
using LibreHardwareMonitor.Hardware;

public sealed class AgentWorker : BackgroundService
{
    private readonly ISensors _sensors;
    private CommandWatcher? _watcher;

    public AgentWorker(ISensors sensors){ _sensors = sensors; }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        Log.Information("Agent online (sensors + commands)");
        var baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil");
        var ipcDir  = Path.Combine(baseDir, "ipc");
        var outFile = Path.Combine(ipcDir, "latest.json");
        Directory.CreateDirectory(ipcDir);

        _watcher = new CommandWatcher(baseDir);
        _watcher.Start(ct);

        while(!ct.IsCancellationRequested)
        {
            var snap = _sensors.ReadOnce();
            try {
                var json = JsonSerializer.Serialize(snap);
                File.WriteAllText(outFile, json);
            } catch (Exception ex) { Log.Error(ex, "IPC write failed"); }
            await Task.Delay(1000, ct);
        }
    }
}

/// <summary>Surveille %ProgramData%\Virgil\ipc\commands et exécute.</summary>
public sealed class CommandWatcher
{
    private readonly string _baseDir;
    private readonly string _cmdDir;

    public CommandWatcher(string baseDir)
    {
        _baseDir = baseDir;
        _cmdDir  = Path.Combine(_baseDir, "ipc", "commands");
        Directory.CreateDirectory(_cmdDir);
    }

    public void Start(CancellationToken ct)
    {
        Task.Run(async () =>
        {
            Log.Information("Command watcher started: {dir}", _cmdDir);
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    var files = Directory.EnumerateFiles(_cmdDir, "*.json").ToList();
                    foreach (var f in files)
                    {
                        CommandRequest? req = null;
                        try { req = JsonSerializer.Deserialize<CommandRequest>(File.ReadAllText(f)); }
                        catch (Exception ex) { Log.Error(ex, "Bad command file {file}", f); }

                        if (req != null)
                        {
                            var res = await ExecuteAsync(req, ct);
                            var resPath = Path.Combine(Path.GetDirectoryName(f)!, Path.GetFileNameWithoutExtension(f) + ".result.json");
                            File.WriteAllText(resPath, JsonSerializer.Serialize(res));
                        }

                        try { File.Delete(f); } catch { /* ignore */ }
                    }
                }
                catch (Exception ex)
                {
                    Log.Error(ex, "Command polling error");
                }
                await Task.Delay(1000, ct);
            }
        }, ct);
    }

    private async Task<CommandResult> ExecuteAsync(CommandRequest req, CancellationToken ct)
    {
        try
        {
            return req.Type switch
            {
                VirgilCommandType.Clean     => await DoCleanupAsync(req, ct),
                VirgilCommandType.UpdateAll => await DoUpdateAllAsync(req, ct),
                _ => new CommandResult(req.CorrelationId, false, "Unknown command", DateTime.UtcNow)
            };
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Execute command failed: {type}", req.Type);
            return new CommandResult(req.CorrelationId, false, ex.Message, DateTime.UtcNow);
        }
    }

    // --------- CLEANUP RÉEL ----------
    private async Task<CommandResult> DoCleanupAsync(CommandRequest req, CancellationToken ct)
    {
        Log.Information("CLEANUP started (real)");
        int files = 0; long bytes = 0;

        void DeleteIn(string path)
        {
            try
            {
                if (!Directory.Exists(path)) return;
                foreach (var f in Directory.EnumerateFiles(path, "*", SearchOption.TopDirectoryOnly))
                {
                    try { var fi = new FileInfo(f); var len = fi.Length; File.SetAttributes(f, FileAttributes.Normal); File.Delete(f); files++; bytes += (long)len; }
                    catch { /* ignore locked */ }
                }
                foreach (var d in Directory.EnumerateDirectories(path))
                {
                    try { Directory.Delete(d, true); }
                    catch { /* ignore locked */ }
                }
            } catch { /* ignore */ }
        }

        // Temp Windows et Prefetch
        DeleteIn(Path.GetTempPath());
        DeleteIn(@"C:\Windows\Temp");
        DeleteIn(@"C:\Windows\Prefetch");

        // Caches navigateurs (profils usuels)
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

        void DelIfExists(string p) { if (Directory.Exists(p)) DeleteIn(p); }

        // Edge
        foreach (var d in Directory.EnumerateDirectories(Path.Combine(local, @"Microsoft\Edge\User Data"), "*", SearchOption.TopDirectoryOnly))
        {
            DelIfExists(Path.Combine(d, "Cache"));
            DelIfExists(Path.Combine(d, "Code Cache"));
        }
        // Chrome
        foreach (var d in Directory.EnumerateDirectories(Path.Combine(local, @"Google\Chrome\User Data"), "*", SearchOption.TopDirectoryOnly))
        {
            DelIfExists(Path.Combine(d, "Cache"));
            DelIfExists(Path.Combine(d, @"Service Worker\CacheStorage"));
            DelIfExists(Path.Combine(d, "Code Cache"));
        }
        // Brave
        foreach (var d in Directory.EnumerateDirectories(Path.Combine(local, @"BraveSoftware\Brave-Browser\User Data"), "*", SearchOption.TopDirectoryOnly))
        {
            DelIfExists(Path.Combine(d, "Cache"));
            DelIfExists(Path.Combine(d, "Code Cache"));
        }
        // Vivaldi
        foreach (var d in Directory.EnumerateDirectories(Path.Combine(local, @"Vivaldi\User Data"), "*", SearchOption.TopDirectoryOnly))
        {
            DelIfExists(Path.Combine(d, "Cache"));
            DelIfExists(Path.Combine(d, "Code Cache"));
        }
        // Opera stable
        DelIfExists(Path.Combine(roaming, @"Opera Software\Opera Stable\Cache"));
        DelIfExists(Path.Combine(roaming, @"Opera Software\Opera Stable\Code Cache"));
        // Opera GX
        DelIfExists(Path.Combine(roaming, @"Opera Software\Opera GX Stable\Cache"));
        DelIfExists(Path.Combine(roaming, @"Opera Software\Opera GX Stable\Code Cache"));
        // Firefox
        var ffProf = Path.Combine(roaming, @"Mozilla\Firefox\Profiles");
        if (Directory.Exists(ffProf))
        {
            foreach (var d in Directory.EnumerateDirectories(ffProf, "*.*", SearchOption.TopDirectoryOnly))
            {
                DelIfExists(Path.Combine(d, "cache2"));
                DelIfExists(Path.Combine(d, "startupCache"));
            }
        }

        // Corbeille
        TryRunPwsh("Clear-RecycleBin -Force");

        Log.Information("CLEANUP done: {files} files, {mb} MB", files, bytes / 1_000_000);
        return new CommandResult(req.CorrelationId, true, $"Cleanup OK: ~{bytes/1_000_000} MB libérés", DateTime.UtcNow);
    }

    // --------- MISES À JOUR RÉELLES ----------
    private async Task<CommandResult> DoUpdateAllAsync(CommandRequest req, CancellationToken ct)
    {
        Log.Information("UPDATE started (real)");

        // 1) Winget full
        TryRun("winget", "upgrade --all --include-unknown --silent --accept-package-agreements --accept-source-agreements", wait:true);

        // 2) Defender signatures + scan COMPLET (long)
        TryRunPwsh("Update-MpSignature");
        TryRunPwsh("Start-MpScan -ScanType FullScan");

        // 3) Windows Update (kickoff)
        TryRun("UsoClient.exe", "StartScan", wait:true);
        TryRun("UsoClient.exe", "StartDownload", wait:true);
        TryRun("UsoClient.exe", "StartInstall", wait:true);

        Log.Information("UPDATE done (commands scheduled/executed)");
        return new CommandResult(req.CorrelationId, true, "Updates triggered (winget/Defender/Windows Update)", DateTime.UtcNow);
    }

    // --- helpers process ---
    private static void TryRun(string file, string args, bool wait=false)
    {
        try {
            var p = new Process();
            p.StartInfo.FileName = file;
            p.StartInfo.Arguments = args;
            p.StartInfo.UseShellExecute = false;
            p.StartInfo.CreateNoWindow = true;
            p.StartInfo.RedirectStandardOutput = true;
            p.StartInfo.RedirectStandardError  = true;
            p.Start();
            if (wait) p.WaitForExit();
        } catch (Exception ex) { Log.Error(ex, "Failed: {file} {args}", file, args); }
    }
    private static void TryRunPwsh(string command)
    {
        TryRun("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command {command}", wait:true);
    }
}

// ---------- Impl capteurs (inchangé) ----------
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
                catch { }
            }
        }

        try
        {
            var di = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory)!);
            if (di.TotalSize > 0) diskFreePct = (float)(100.0 * di.TotalFreeSpace / di.TotalSize);
        } catch { }

        return new MetricsSnapshot(cpuLoad, gpuLoad, gpuTemp, ramPct, diskFreePct, topProc, at);
    }

    public void Dispose(){ try { _pc.Close(); } catch { } }
}
'@
W ".\src\$Sln.Agent\CommandWatcher.cs" $agentCmd

# Assure les références déjà OK
dotnet add $projAgent package LibreHardwareMonitorLib | Out-Null

# --- 2) UI : deux boutons et émission de commandes ---
# XAML : ajoute un panneau d'actions dans la colonne de droite (sous "Bulles (mock)")
$xamlPath = ".\src\$Sln.UI\MainWindow.xaml"
$xaml = Get-Content $xamlPath -Raw
if ($xaml -notmatch 'Nettoyage complet')
{
  $xaml = $xaml -replace '(?<end></ScrollViewer>\s*</Border>\s*</Grid>\s*</Window>)', @"
  <StackPanel Orientation="Vertical" Margin="16,8,16,16">
    <TextBlock Text="Actions" Foreground="#7AA" FontSize="16" Margin="0,8,0,6"/>
    <StackPanel Orientation="Horizontal">
      <Button x:Name="BtnClean" Content="Nettoyage complet" Width="180" Height="32" Margin="0,0,8,0" Click="BtnClean_Click"/>
      <Button x:Name="BtnUpdate" Content="Mises à jour (Tout)" Width="180" Height="32" Click="BtnUpdate_Click"/>
    </StackPanel>
    <TextBlock x:Name="ActionStatus" Foreground="#9bd" Margin="0,8,0,0"/>
  </StackPanel>
$1
"@
  $xaml | Set-Content $xamlPath -Encoding UTF8
}

# Code-behind : écriture des commandes JSON + petit retour visuel
$uiCsPath = ".\src\$Sln.UI\MainWindow.xaml.cs"
$uiCs = Get-Content $uiCsPath -Raw

if ($uiCs -notmatch 'SendCommand')
{
$uiCs = $uiCs + @'

using System.IO;
using System.Text.Json;
using Virgil.Core;

namespace Virgil.UI
{
    public partial class MainWindow
    {
        private string CommandDir => Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.CommonApplicationData), "Virgil", "ipc", "commands");

        private void SendCommand(VirgilCommandType type)
        {
            Directory.CreateDirectory(CommandDir);
            var id = System.Guid.NewGuid().ToString("N");
            var req = new CommandRequest(type, id, System.DateTime.UtcNow);
            var json = JsonSerializer.Serialize(req);
            var path = Path.Combine(CommandDir, $"{id}.json");
            File.WriteAllText(path, json);
            ActionStatus.Text = $"Commande {type} envoyée ({id[..8]}…)";
        }

        private void BtnClean_Click(object sender, System.Windows.RoutedEventArgs e) => SendCommand(VirgilCommandType.Clean);
        private void BtnUpdate_Click(object sender, System.Windows.RoutedEventArgs e) => SendCommand(VirgilCommandType.UpdateAll);
    }
}
'@
Set-Content $uiCsPath $uiCs -Encoding UTF8
}

# --- 3) Build final ---
dotnet build -c Release
Write-Host "`n✅ Actions intégrées : Nettoyage + Mises à jour (réel)."
Write-Host "   1) Lance l'Agent :  dotnet run --project .\src\$Sln.Agent\$Sln.Agent.csproj"
Write-Host "   2) Ouvre l'UI   :  & .\src\$Sln.UI\bin\Release\net8.0-windows\$Sln.UI.exe"
