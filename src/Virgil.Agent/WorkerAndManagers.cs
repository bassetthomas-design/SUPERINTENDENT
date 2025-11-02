using Microsoft.Extensions.Hosting;
using Serilog;
using System;
using System.Threading;
using System.Threading.Tasks;
using Virgil.Core;

using Virgil.Agent;
public sealed class AgentWorker : BackgroundService
{
    private readonly ISensors _sensors;
    private readonly CommandWatcher _watcher;

    public AgentWorker(ISensors sensors, CommandWatcher watcher)
    {
        _sensors = sensors;
        _watcher = watcher;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        Log.Information("Agent online");
        _watcher.Start(System.Threading.CancellationToken.None); // <--- important : démarre l'écoute des commandes

        while(!ct.IsCancellationRequested)
        {
            var snap = _sensors.ReadOnce();
            // TODO: publier vers l’UI (pipe/SignalR) — plus tard
            await Task.Delay(1000, ct);
        }
    }
}

public sealed class SensorManager : ISensors
{
    public MetricsSnapshot ReadOnce()
    {
        var r = new Random();
        return new MetricsSnapshot(
            CpuPct:     r.Next(5,90),
            GpuPct:     r.Next(3,80),
            GpuTempC:   r.Next(40,88),
            RamPct:     r.Next(20,92),
            DiskFreePct:r.Next(5,80),
            TopProcess: "explorer.exe",
            AtUtc:      DateTime.UtcNow
        );
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




