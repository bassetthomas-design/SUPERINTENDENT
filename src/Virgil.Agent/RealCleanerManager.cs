using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Virgil.Core;

public sealed class RealCleanerManager : ICleaner
{
    private sealed record Group(string name, string[] paths);
    private sealed record CleanupCfg(List<Group> groups, List<string> exclusions);

    public async Task<CleanupReport> RunAsync(CleanupRequest req, CancellationToken ct)
    {
        var cfgFile = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "data", "cleanup_targets.json");
        if (!File.Exists(cfgFile))
            cfgFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil", "cleanup_targets.json");
        var json = File.Exists(cfgFile) ? File.ReadAllText(cfgFile) : "{\"groups\":[],\"exclusions\":[]}";
        var cfg = JsonSerializer.Deserialize<CleanupCfg>(json, new JsonSerializerOptions{PropertyNameCaseInsensitive = true}) ?? new CleanupCfg(new(), new());

        var groupsToRun = new List<Group>();
        if (req.Groups is {Length:>0})
        {
            foreach(var g in cfg.groups)
                if (Array.Exists(req.Groups, x => string.Equals(x, g.name, StringComparison.OrdinalIgnoreCase)))
                    groupsToRun.Add(g);
        }
        else
        {
            groupsToRun.AddRange(cfg.groups);
        }

        long files = 0;
        long bytes = 0;
        var done = new List<string>();
        var errors = new List<string>();

        foreach (var g in groupsToRun)
        {
            try
            {
                foreach (var pattern in g.paths)
                {
                    if (ct.IsCancellationRequested) break;

                    var expanded = Environment.ExpandEnvironmentVariables(pattern);
                    var isWildcard = expanded.Contains("*") || expanded.Contains("?");
                    var basePath = expanded;

                    // Resolve wildcard enumeration safely
                    if (isWildcard)
                    {
                        var dir = Path.GetDirectoryName(expanded) ?? expanded;
                        var mask = Path.GetFileName(expanded);
                        if (Directory.Exists(dir))
                        {
                            // Files
                            foreach (var f in Directory.EnumerateFiles(dir, mask, SearchOption.TopDirectoryOnly))
                            {
                                TryDeleteFile(f, ref files, ref bytes, errors, req.Simulation);
                            }
                            // Dirs
                            foreach (var d in Directory.EnumerateDirectories(dir, mask, SearchOption.TopDirectoryOnly))
                            {
                                TryDeleteDir(d, ref files, ref bytes, errors, req.Simulation);
                            }
                        }
                    }
                    else
                    {
                        if (File.Exists(basePath)) TryDeleteFile(basePath, ref files, ref bytes, errors, req.Simulation);
                        else if (Directory.Exists(basePath)) TryDeleteDir(basePath, ref files, ref bytes, errors, req.Simulation);
                    }
                }
                done.Add(g.name);
            }
            catch (Exception ex)
            {
                errors.Add($"{g.name}: {ex.Message}");
            }
        }

        await Task.CompletedTask;
        return new CleanupReport(files, bytes, done, errors);
    }

    private static void TryDeleteFile(string path, ref long files, ref long bytes, List<string> errors, bool simulate)
    {
        try
        {
            var fi = new FileInfo(path);
            bytes += fi.Exists ? fi.Length : 0;
            if (!simulate && fi.Exists)
                fi.Attributes = FileAttributes.Normal;
            if (!simulate && fi.Exists)
                fi.Delete();
            files += 1;
        }
        catch (Exception ex)
        {
            errors.Add($"file {path}: {ex.Message}");
        }
    }

    private static void TryDeleteDir(string dir, ref long files, ref long bytes, List<string> errors, bool simulate)
    {
        try
        {
            if (!Directory.Exists(dir)) return;
            foreach (var f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
            {
                TryDeleteFile(f, ref files, ref bytes, errors, simulate);
            }
            if (!simulate)
                Directory.Delete(dir, true);
        }
        catch (Exception ex)
        {
            errors.Add($"dir {dir}: {ex.Message}");
        }
    }
}

