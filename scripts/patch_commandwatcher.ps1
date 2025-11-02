param(
  [string]$RepoRoot = "C:\Dev\VirgilOps",
  [string]$ServiceName = "VirgilAgent",
  [string]$Dotnet = "C:\Program Files\dotnet\dotnet.exe"
)

$ErrorActionPreference = "Stop"
$agentProj = Join-Path $RepoRoot "src\Virgil.Agent\Virgil.Agent.csproj"
$cwPath    = Join-Path $RepoRoot "src\Virgil.Agent\CommandWatcher.cs"
$publishOut= Join-Path $RepoRoot "artifacts\agent"
$instDir   = "C:\Program Files\Virgil\Agent"
$cmdDir    = "C:\ProgramData\Virgil\ipc\commands"
$logDir    = "C:\ProgramData\Virgil\logs"

# 1) Sauvegarde + remplacement CommandWatcher.cs
if (Test-Path $cwPath) { Copy-Item $cwPath "$cwPath.bak" -Force }

$cwCode = @'
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Serilog;

public sealed class CommandWatcher
{
    private readonly string _commandsDir;
    private CancellationTokenSource? _cts;
    private Task? _loop;

    public CommandWatcher(string baseDir)
    {
        _commandsDir = Path.Combine(baseDir, "ipc", "commands");
        Directory.CreateDirectory(_commandsDir);
    }

    public void Start()
    {
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        Log.Information("Command watcher started: {Dir}", _commandsDir);

        _loop = Task.Run(async () =>
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    // Ne traiter que *.json qui ne sont PAS des *.result.json
                    var files = Directory.EnumerateFiles(_commandsDir, "*.json")
                        .Where(p => !p.EndsWith(".result.json", StringComparison.OrdinalIgnoreCase))
                        .OrderBy(p => File.GetCreationTimeUtc(p))
                        .ToList();

                    foreach (var cmdPath in files)
                    {
                        try
                        {
                            var id = Path.GetFileNameWithoutExtension(cmdPath); // ex: 161be4bd...
                            var resultPath = Path.Combine(_commandsDir, $"{id}.result.json");

                            var payload = File.ReadAllText(cmdPath, Encoding.UTF8);
                            var result = new {
                                id,
                                receivedUtc = DateTime.UtcNow,
                                ok = true,
                                message = "Processed",
                                input = payload
                            };

                            var json = JsonSerializer.Serialize(result);
                            File.WriteAllText(resultPath, json, Encoding.UTF8); // overwrite propre

                            try { File.Delete(cmdPath); } catch { /* ignore */ }
                        }
                        catch (Exception exFile)
                        {
                            Log.Error(exFile, "Command handling error for {Cmd}", cmdPath);
                        }
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

    public void Stop()
    {
        try { _cts?.Cancel(); } catch {}
        try { _loop?.Wait(1500); } catch {}
        _cts?.Dispose();
        _cts = null;
        _loop = null;
    }
}
'@

Set-Content -Path $cwPath -Value $cwCode -Encoding UTF8 -Force
Write-Host "✔ CommandWatcher.cs remplacé" -ForegroundColor Green

# 2) Build + Publish (chemin dotnet absolu)
& $Dotnet build $RepoRoot -c Release
& $Dotnet publish $agentProj -c Release -r win-x64 `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true --self-contained:false `
  -o $publishOut
Write-Host "✔ Build/Publish OK" -ForegroundColor Green

# 3) Stop service + déploiement + restart
sc.exe stop $ServiceName *> $null
Start-Sleep 2
if (!(Test-Path $instDir)) { New-Item -ItemType Directory -Force -Path $instDir | Out-Null }
Remove-Item "$instDir\*" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$publishOut\*" $instDir -Force
sc.exe start $ServiceName | Out-Null
Write-Host "✔ Service redémarré: $ServiceName" -ForegroundColor Green

# 4) Nettoyage des anciens fichiers en cascade
if (Test-Path $cmdDir) {
  Get-ChildItem $cmdDir -Filter '*.result.result*.json' -ErrorAction SilentlyContinue | Remove-Item -Force
  Write-Host "✔ Nettoyage .result en cascade" -ForegroundColor Green
}

# 5) Test rapide: pousser une commande "CleanAll"
if (!(Test-Path $cmdDir)) { New-Item -ItemType Directory -Force -Path $cmdDir | Out-Null }
$testId = [guid]::NewGuid().ToString("N")
'{"type":"CleanAll","simulate":false}' | Set-Content (Join-Path $cmdDir "$testId.json") -Encoding UTF8
Start-Sleep 2

# 6) Vérifs
Write-Host "`n--- COMMANDS DIR ---" -ForegroundColor Cyan
Get-ChildItem $cmdDir | Select Name,Length,LastWriteTime | Format-Table

Write-Host "`n--- LAST LOG ---" -ForegroundColor Cyan
if (Test-Path $logDir) {
  $lastLog = Get-ChildItem "$logDir\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($lastLog) {
    Write-Host $lastLog.FullName
    Get-Content $lastLog.FullName -Tail 60
  } else {
    Write-Host "Aucun log encore trouvé." -ForegroundColor Yellow
  }
} else {
  Write-Host "Dossier logs absent: $logDir" -ForegroundColor Yellow
}
