using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Timers;

namespace Virgil.UI.Services
{
    public static class EmotionRuntime
    {
        private static readonly Random _rng = new();
        private static System.Timers.Timer? _phraseTimer;
        private static bool _enabled = true;
        private static string[] _phrases = Array.Empty<string>();

        public static event Action<string>? OnSay;

        public static void Init()
        {
            LoadPhrases();
            ScheduleNext();
        }

        public static void SetEnabled(bool enabled)
        {
            _enabled = enabled;
            if (_enabled) ScheduleNext();
            else StopTimer();
        }

        public static void SayRandom()
        {
            string text = PickRandomPhrase();
            OnSay?.Invoke(text);
            ScheduleNext();
        }

        private static void LoadPhrases()
        {
            try {
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "phrases.json");
                if (File.Exists(path))
                {
                    var json = File.ReadAllText(path);
                    var arr = JsonSerializer.Deserialize<string[]>(json);
                    if (arr != null && arr.Length > 0) _phrases = arr.Where(s => !string.IsNullOrWhiteSpace(s)).ToArray();
                }
            } catch { }
            if (_phrases.Length == 0) _phrases = new[] { "Je veille..." };
        }

        private static string PickRandomPhrase()
        {
            if (_phrases.Length == 0) return "Je veille...";
            return _phrases[_rng.Next(_phrases.Length)];
        }

        private static void ScheduleNext()
        {
            StopTimer();
            if (!_enabled) return;
            int nextSeconds = _rng.Next(60, 601); // 1 à 10 minutes
            _phraseTimer = new System.Timers.Timer(nextSeconds * 1000);
            _phraseTimer.AutoReset = false;
            _phraseTimer.Elapsed += (s, e) => SayRandom();
            _phraseTimer.Start();
        }

        private static void StopTimer()
        {
            if (_phraseTimer != null)
            {
                try { _phraseTimer.Stop(); } catch {}
                try { _phraseTimer.Dispose(); } catch {}
                _phraseTimer = null;
            }
        }
    }
}

