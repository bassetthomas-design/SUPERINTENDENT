using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows.Threading;
using Virgil.Core;

namespace Virgil.UI;

public sealed class EventSubscriber : IDisposable
{
    private readonly string _dir;
    private readonly FileSystemWatcher _fsw;
    private readonly Dispatcher _dispatch;
    public ObservableCollection<string> Lines { get; } = new();

    public EventSubscriber()
    {
        _dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil", "ipc", "events");
        Directory.CreateDirectory(_dir);
        _dispatch = Dispatcher.CurrentDispatcher;

        _fsw = new FileSystemWatcher(_dir, "evt_*.json"){ EnableRaisingEvents = true, IncludeSubdirectories = false };
        _fsw.Created += (s,e) => TryLoad(e.FullPath);
        // bootstrap: lire les 10 derniers
        foreach(var f in new DirectoryInfo(_dir).GetFiles("evt_*.json").OrderByDescending(x => x.LastWriteTimeUtc).Take(10).OrderBy(x=>x.LastWriteTimeUtc))
            TryLoad(f.FullName);
    }

    private void TryLoad(string path)
    {
        try
        {
            // attend que le fichier soit prêt
            for (int i=0;i<10;i++){ try { using var _ = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read); break; } catch { System.Threading.Thread.Sleep(20);} }
            var json = File.ReadAllText(path);
            using var doc = JsonDocument.Parse(json);
            var kind = doc.RootElement.GetProperty("Kind").GetString() ?? "Event";
            var when = doc.RootElement.GetProperty("AtUtc").GetDateTime();
            var msg  = doc.RootElement.GetProperty("Message").GetString() ?? kind;
            var line = $"[{when:HH:mm:ss}] {msg}";
            _dispatch.Invoke(()=> Lines.Add(line));
        }
        catch { /* ignore */ }
    }

    public void Dispose() => _fsw?.Dispose();
}
