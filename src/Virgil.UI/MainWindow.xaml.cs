using System;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using Virgil.Core;

namespace Virgil.UI
{
    public partial class MainWindow : Window
    {
        private readonly string _ipcFile;
        private readonly DispatcherTimer _timer;

        public MainWindow()
        {
            InitializeComponent();
            _ipcFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil", "ipc", "latest.json");
            _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _timer.Tick += (s,e) => RefreshMetrics();
            _timer.Start();
        }

        private void RefreshMetrics()
        {
            try
            {
                if (!File.Exists(_ipcFile)) return;
                var json = File.ReadAllText(_ipcFile);
                var snap = JsonSerializer.Deserialize<MetricsSnapshot>(json);
                if (snap == null) return;

                CpuBar.Value  = snap.CpuPct;   CpuLbl.Text  = $"{snap.CpuPct:0}%";
                GpuBar.Value  = snap.GpuPct;   GpuTemp.Text = $"{snap.GpuTempC:0}°C";
                RamBar.Value  = snap.RamPct;   RamLbl.Text  = $"{snap.RamPct:0}%";
                DiskBar.Value = snap.DiskFreePct; DiskLbl.Text = $"{snap.DiskFreePct:0}%";
                TopProc.Text  = snap.TopProcess ?? "n/a";
                Updated.Text  = $"Updated: {DateTime.Now:HH:mm:ss}";
            }
            catch { /* UI: tolérant aux erreurs */ }
        }

        private string CommandDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil", "ipc", "commands");

        private void SendCommand(CommandType type)
        {
            Directory.CreateDirectory(CommandDir);
            var id = Guid.NewGuid().ToString("N");
            var req = new CommandRequest(type, id);
            var json = JsonSerializer.Serialize(req);
            var path = Path.Combine(CommandDir, $"{id}.json");
            File.WriteAllText(path, json);
            ActionStatus.Text = $"Commande {type} envoyée ({id[..8]}…)";
        }

        private void BtnClean_Click(object sender, RoutedEventArgs e)  => SendCommand(CommandType.CleanAll);
        private void BtnUpdate_Click(object sender, RoutedEventArgs e) => SendCommand(CommandType.UpdateAll);
    }
}








