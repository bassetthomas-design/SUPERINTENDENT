using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Timers;
using Virgil.UI.Services;

namespace Virgil.UI.ViewModels
{
    public partial class MainViewModel : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;
        void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

        private bool _monitoringEnabled;
        public bool MonitoringEnabled
        {
            get => _monitoringEnabled;
            set
            {
                if (_monitoringEnabled != value)
                {
                    _monitoringEnabled = value;
                    EmotionRuntime.SetEnabled(_monitoringEnabled);
                    OnPropertyChanged();
                }
            }
        }

        public RelayCommand ToggleMonitorCommand { get; }
        public RelayCommand SayRandomCommand { get; }

        public MainViewModel()
        {
            ToggleMonitorCommand = new RelayCommand(_ => MonitoringEnabled = !MonitoringEnabled);
            SayRandomCommand = new RelayCommand(_ => EmotionRuntime.ForceSpeakOnce());
        }
    }
}


