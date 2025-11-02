using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Timers;

namespace Virgil.UI.Services
{
    public static class EmotionRuntime
    {
        private static readonly Random _rng = new Random();
        private static readonly List<string> _phrases = new List<string>();
        private static System.Timers.Timer? _timer;
        private static bool _enabled;

        public static bool IsEnabled => _enabled;

        public static void Init(string baseDir)
        {
            try
            {
                var phrasesPath = Path.Combine(baseDir, "Assets", "phrases.json");
                if (File.Exists(phrasesPath))
                {
                    var json = File.ReadAllText(phrasesPath);
                    var list = JsonSerializer.Deserialize<List<string>>(json);
                    if (list != null)
                    {
                        _phrases.Clear();
                        _phrases.AddRange(list);
                    }
                }
            }
            catch
            {
                // ignore
            }

            EnsureTimer();
        }

        public static void SetEnabled(bool enabled)
        {
            _enabled = enabled;
            EnsureTimer();
        }

        public static void ForceSpeakOnce()
        {
            if (_phrases.Count == 0) return;
            var idx = _rng.Next(_phrases.Count);
            var text = _phrases[idx];
            // TODO: brancher vers la UI (bulle / chat)
            System.Diagnostics.Debug.WriteLine($"[Virgil] {text}");
        }

        private static void EnsureTimer()
        {
            if (_timer == null)
            {
                _timer = new System.Timers.Timer();
                _timer.AutoReset = false;
                _timer.Elapsed += OnTick;
            }

            if (_enabled)
            {
                _timer.Interval = NextDelayMs();
                _timer.Start();
            }
            else
            {
                _timer.Stop();
            }
        }

        private static void OnTick(object? s, System.Timers.ElapsedEventArgs e)
        {
            try
            {
                if (_enabled) ForceSpeakOnce();
            }
            finally
            {
                if (_enabled && _timer != null)
                {
                    _timer.Interval = NextDelayMs();
                    _timer.Start();
                }
            }
        }

        private static double NextDelayMs()
        {
            // 1 à 10 minutes
            var minutes = _rng.Next(1, 11);
            return TimeSpan.FromMinutes(minutes).TotalMilliseconds;
        }
    }
}
