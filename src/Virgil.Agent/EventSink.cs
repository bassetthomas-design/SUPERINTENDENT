using System;
using System.IO;
using System.Text.Json;
using Virgil.Core;

public interface IEventSink { void Publish(VirgilEvent e); }

public sealed class FileEventSink : IEventSink
{
    private readonly string _dir;
    private readonly JsonSerializerOptions _json = new(JsonSerializerOptions.Default) { WriteIndented = false };

    public FileEventSink(string baseDir)
    {
        _dir = Path.Combine(baseDir, "ipc", "events");
        Directory.CreateDirectory(_dir);
    }

    public void Publish(VirgilEvent e)
    {
        var id = $"{DateTime.UtcNow:yyyyMMdd_HHmmss_fff}_{Guid.NewGuid():N}";
        var path = Path.Combine(_dir, $"evt_{id}.json");
        var json = JsonSerializer.Serialize(e, e.GetType(), _json);
        File.WriteAllText(path, json);
    }
}

