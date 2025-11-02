using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Virgil.Core;

public sealed class RealUpdaterManager : IUpdater
{
    public async Task<UpdateReport> RunAsync(UpdateRequest req, CancellationToken ct)
    {
        var errors = new System.Collections.Generic.List<string>();
        var sourcesDone = new System.Collections.Generic.List<string>();
        int items = 0;
        long bytes = 0;

        // 2.1 Winget upgrades (silencieux autant que possible)
        try
        {
            var (code, _) = Run("winget", "upgrade --all --silent --accept-source-agreements --accept-package-agreements", 60*30);
            sourcesDone.Add("winget");
            if (code == 0) items += 1; else errors.Add("winget returned " + code);
        }
        catch(Exception ex){ errors.Add("winget: " + ex.Message); }

        // 2.2 Defender: signature + scan rapide
        try
        {
            var mp = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Windows Defender", "MpCmdRun.exe");
            if (File.Exists(mp))
            {
                Run(mp, "-SignatureUpdate", 300);
                sourcesDone.Add("defender_defs");
                Run(mp, "-Scan -ScanType 1", 60*20);
                sourcesDone.Add("defender_quickscan");
                items += 1;
            }
        }
        catch(Exception ex){ errors.Add("defender: " + ex.Message); }

        // 2.3 Windows Update: scan (+ téléchargement/installation si possible)
        try
        {
            // Best effort: usoclient reste non-documenté mais présent sur la plupart des machines
            Run("UsoClient.exe", "StartScan", 120);
            sourcesDone.Add("windows_update_scan");
            // (optionnel) : StartDownload / StartInstall selon politiques
            Run("UsoClient.exe", "StartDownload", 120);
            Run("UsoClient.exe", "StartInstall", 120);
            sourcesDone.Add("windows_update_apply");
            items += 1;
        }
        catch(Exception ex){ errors.Add("windows_update: " + ex.Message); }

        await Task.CompletedTask;
        return new UpdateReport(items, bytes, sourcesDone, errors);
    }

    private static (int code, string output) Run(string file, string args, int timeoutSec)
    {
        var psi = new ProcessStartInfo(file, args)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var p = Process.Start(psi)!;
        if (!p.WaitForExit(timeoutSec * 1000))
        {
            try { p.Kill(true); } catch { }
            throw new TimeoutException($"{file} {args} timed out");
        }
        var outp = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        return (p.ExitCode, outp);
    }
}

