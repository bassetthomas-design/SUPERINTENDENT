using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace Virgil.UI.ViewModels
{
    public enum AvatarMood { Idle, Happy, Thinking, Alert, Focus, Gaming, Browsing, Working }

    public class EmotionEngine
    {
        private readonly Random _rng = new Random();
        private readonly List<string> _phrases = new();
        public event Action<AvatarMood>? MoodChanged;
        public event Action<string>? SpontaneousLine; // phrase aléatoire
        public AvatarMood Current { get; private set; } = AvatarMood.Idle;

        private System.Timers.Timer? _idleTimer;
        private System.Timers.Timer? _chatterTimer;
        private readonly Func<bool> _isBusyFunc;

        public EmotionEngine(string? phrasesPath, Func<bool> isBusyFunc)
        {
            _isBusyFunc = isBusyFunc;
            if (!string.IsNullOrWhiteSpace(phrasesPath) && File.Exists(phrasesPath))
            {
                try
                {
                    var json = File.ReadAllText(phrasesPath);
                    var arr = JsonSerializer.Deserialize<string[]>(json);
                    if (arr != null) _phrases.AddRange(arr.Where(s => !string.IsNullOrWhiteSpace(s)));
                }
                catch { /* swallow, keep default empty */ }
            }
        }

        public void Start()
        {
            _idleTimer = new System.Timers.Timer(15000); // 15s pour basculer Idle si pas d'activité
            _idleTimer.Elapsed += (_, __) => { if(!_isBusyFunc()) SetMood(AvatarMood.Idle); };
            _idleTimer.AutoReset = true;
            _idleTimer.Start();

            _chatterTimer = new System.Timers.Timer(GetNextChatterMs());
            _chatterTimer.Elapsed += (_, __) =>
            {
                try
                {
                    if (_phrases.Count > 0)
                    {
                        var msg = _phrases[_rng.Next(_phrases.Count)];
                        SpontaneousLine?.Invoke(msg);
                    }
                }
                finally
                {
                    if (_chatterTimer != null)
                    {
                        _chatterTimer.Interval = GetNextChatterMs(); // rearm aléatoire 1–10 min
                    }
                }
            };
            _chatterTimer.AutoReset = true;
            _chatterTimer.Start();
        }

        public void Stop()
        {
            _idleTimer?.Stop(); _idleTimer?.Dispose();
            _chatterTimer?.Stop(); _chatterTimer?.Dispose();
        }

        public void SetMood(AvatarMood mood)
        {
            if (mood == Current) return;
            Current = mood;
            MoodChanged?.Invoke(mood);
        }

        private double GetNextChatterMs() => _rng.Next(1, 11) * 60_000; // 1..10 minutes
    }
}
