using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Virgil.Core;

namespace Virgil.Agent
{
    public interface IEventSink { void Info(string m); void Error(string m, Exception ex); } // garde-fou si ton impl existe déjà

    public sealed class CommandWatcher
    {
        private readonly string _dir;
        private readonly IEventSink? _events;
        private readonly JsonSerializerOptions _json;

        private static readonly Regex GuidN = new(@"(?i)[0-9a-f]{32}", RegexOptions.Compiled);

        public CommandWatcher(string dir, IEventSink? events = null)
        {
            _dir = dir;
            _events = events;
            Directory.CreateDirectory(_dir);
            _json = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
                NumberHandling = JsonNumberHandling.AllowReadingFromString
            };
        }

        public void Start(CancellationToken token)
        {
            _ = Task.Run(() => LoopAsync(token), token);
        }

        private async Task LoopAsync(CancellationToken token)
        {
            // Scan initial
            foreach (var f in Directory.EnumerateFiles(_dir, "*.json"))
                await TryHandleAsync(f, token);

            // Petit timer (le FileSystemWatcher n'est pas indispensable ici)
            while (!token.IsCancellationRequested)
            {
                foreach (var f in Directory.EnumerateFiles(_dir, "*.json"))
                    await TryHandleAsync(f, token);

                await Task.Delay(500, token);
            }
        }

        private async Task TryHandleAsync(string path, CancellationToken token)
        {
            var name = Path.GetFileName(path);
            if (name == null) return;

            // Ne jamais re-traiter un résultat
            if (name.EndsWith(".result.json", StringComparison.OrdinalIgnoreCase)) return;

            // Extrait l'ID depuis le contenu (fallback: depuis le nom du fichier)
            string json;
            try { json = await File.ReadAllTextAsync(path, token).ConfigureAwait(false); }
            catch { return; }

            string? id = null;
            try
            {
                using var doc = JsonDocument.Parse(json);
                if (doc.RootElement.TryGetProperty("Id", out var idEl))
                    id = idEl.GetString();
            }
            catch { /* bad json → handled below */ }

            if (string.IsNullOrWhiteSpace(id))
            {
                var m = GuidN.Match(name);
                if (m.Success) id = m.Value;
            }
            if (string.IsNullOrWhiteSpace(id)) return;

            // Désérialise CommandRequest (tolérant string/numérique + case-insensitive)
            CommandRequest? cmd;
            try { cmd = JsonSerializer.Deserialize<CommandRequest>(json, _json); }
            catch (Exception ex)
            {
                _events?.Error($"Bad command file {path}", ex);
                // on le garde pour diagnostic, mais on n'écrit pas de .result
                return;
            }
            if (cmd is null) return;

            // Map du Type
            Func<CancellationToken, Task<CommandResponse>>? action = cmd.Type switch
            {
                Virgil.Core.CommandType.CleanAll  => CleanAsync,
                Virgil.Core.CommandType.UpdateAll => UpdateAsync,
                _ => null
            };
            if (action is null) return;

            // Exécute
            CommandResponse result;
            try { result = await action(token).ConfigureAwait(false); }
            catch (Exception ex)
            {
                _events?.Error("Command execution error", ex);
                result = new CommandResponse(false, cmd.Type.ToString(), ex.Message);
            }

            // Chemin de résultat NORMALISÉ: <id>.result.json
            var resPath = Path.Combine(_dir, $"{id}.result.json");

            // Purge les variantes polluées (sauf le bon chemin)
            foreach (var g in Directory.EnumerateFiles(_dir, $"{id}*.result*.json"))
            {
                try { if (!g.Equals(resPath, StringComparison.OrdinalIgnoreCase)) File.Delete(g); } catch { }
            }

            // Écrit le résultat UNE FOIS
            try
            {
                var resJson = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = false });
                await File.WriteAllTextAsync(resPath, resJson, token).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                _events?.Error("Result write error", ex);
            }

            // Supprime tous les fichiers commande de cet id (base/.cmd/.command)
            foreach (var g in Directory.EnumerateFiles(_dir, $"{id}*.json"))
            {
                if (g.EndsWith(".result.json", StringComparison.OrdinalIgnoreCase)) continue;
                try { File.Delete(g); } catch { }
            }
        }

        // Stubs: branche tes vraies implémentations ici (elles existent déjà chez toi)
        private Task<CommandResponse> CleanAsync(CancellationToken _) =>
            Task.FromResult(new CommandResponse(true, "Clean", "ACK"));

        private Task<CommandResponse> UpdateAsync(CancellationToken _) =>
            Task.FromResult(new CommandResponse(true, "UpdateAll", "ACK"));
    }
}




