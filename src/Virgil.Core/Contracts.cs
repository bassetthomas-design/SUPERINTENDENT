namespace Virgil.Core;
public interface ICleaner { System.Threading.Tasks.Task<CleanupReport> RunAsync(CleanupRequest req, System.Threading.CancellationToken ct); }
public interface IUpdater { System.Threading.Tasks.Task<UpdateReport> RunAsync(UpdateRequest req, System.Threading.CancellationToken ct); }
public interface ISensors { MetricsSnapshot ReadOnce(); }
public record CleanupRequest(string Level="complet", string[]? Groups=null, bool Simulation=false);
public record CleanupReport(long Files, long BytesFreed, System.Collections.Generic.IReadOnlyList<string> GroupsDone, System.Collections.Generic.IReadOnlyList<string> Errors);
public record UpdateRequest(string[]? Sources);
public record UpdateReport(int ItemsUpdated, long BytesDownloaded, System.Collections.Generic.IReadOnlyList<string> SourcesDone, System.Collections.Generic.IReadOnlyList<string> Errors);
public record MetricsSnapshot(float CpuPct,float GpuPct,float GpuTempC,float RamPct,float DiskFreePct,string? TopProcess,System.DateTime AtUtc);
