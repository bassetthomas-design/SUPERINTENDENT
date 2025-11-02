using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Virgil.UI.Services;

namespace Virgil.UI.ViewModels
{
    public class MainViewModel : INotifyPropertyChanged
    {
        public RelayCommand ToggleMonitorCommand { get; }
        public RelayCommand SayRandomCommand { get; }

        private bool _monitoringEnabled;
        private readonly MonitoringService _monitor;

        public ObservableCollection<string> Messages { get; } = new();

        public bool MonitoringEnabled
        {
            get => _monitoringEnabled;
            set
            {
                if (_monitoringEnabled == value) return;
                _monitoringEnabled = value;
                OnPropertyChanged();
                _monitor.SetEnabled(value);
            }
        }

        public MainViewModel()
        {
            _monitor = new MonitoringService();
            ToggleMonitorCommand = new RelayCommand(_ => MonitoringEnabled = !MonitoringEnabled);
            SayRandomCommand = new RelayCommand(_ => EmotionRuntime.SayRandom());

            EmotionRuntime.OnSay += (text) =>
            {
                App.Current.Dispatcher.Invoke(() => Messages.Add($"Virgil : {text}"));
            };

            _monitor.OnSample += (cpu, mem) =>
            {
                // Ici plus tard : binder à l’UI (side panel), jauges, etc.
                // Messages.Add($"CPU {cpu:N0}% | RAM {mem:N0}%");
            };
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? name = null)
            => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
