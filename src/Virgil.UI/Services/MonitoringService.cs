using System;
using STimers = System.Timers;

namespace Virgil.UI.Services
{
    public sealed class MonitorSample
    {
        public double Cpu { get; set; }
        public double Gpu { get; set; }
        public double Ram { get; set; }
        public string Activity { get; set; } = "idle";
        public DateTime Timestamp { get; set; } = DateTime.Now;
    }

    public sealed class MonitoringService : IDisposable
    {
        private readonly STimers.Timer _timer;
        private readonly Random _rng = new Random();
        public bool Enabled { get; private set; }

        /// <summary>
        /// Evénement levé à chaque échantillon.
        /// MainViewModel s’y abonne via: monitoring.OnSample += sample => { ... };
        /// </summary>
        public event Action<object, MonitorSample>? OnSample;

        public MonitoringService(double intervalMs = 2000)
        {
            _timer = new STimers.Timer(intervalMs);
            _timer.AutoReset = true;
            _timer.Elapsed += (_, __) => Tick();
        }

        public void SetEnabled(bool enabled)
        {
            if (enabled == Enabled) return;
            Enabled = enabled;
            if (Enabled) _timer.Start();
            else _timer.Stop();
        }

        private void Tick()
        {
            // TODO: remplacer par de vraies mesures CPU/GPU/RAM
            var sample = new MonitorSample
            {
                Cpu = Clamp(NextDrift(35, 25)), // valeurs plausibles de démo
                Gpu = Clamp(NextDrift(20, 30)),
                Ram = Clamp(NextDrift(45, 15)),
                Activity = GuessActivity()
            };
            OnSample?.Invoke(this, sample);
        }

        private double NextDrift(double baseValue, double spread)
        {
            // bruit gaussien simple via somme de rand
            double r = (_rng.NextDouble() + _rng.NextDouble() + _rng.NextDouble()) / 3.0; // ~triangulaire
            return baseValue + (r - 0.5) * 2.0 * spread;
        }

        private static double Clamp(double v) => v < 0 ? 0 : (v > 100 ? 100 : v);

        private string GuessActivity()
        {
            // Démo: bascule aléatoire entre quelques états
            int n = _rng.Next(0, 100);
            if (n < 10) return "gaming";
            if (n < 25) return "browsing";
            if (n < 40) return "working";
            return "idle";
        }

        public void Dispose()
        {
            _timer.Stop();
            _timer.Dispose();
        }
    }
}

