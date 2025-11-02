$ErrorActionPreference = ''Stop''
$root = ''C:\Dev\VirgilOps''
$ui   = Join-Path $root ''src\Virgil.UI''
$csproj = Join-Path $ui ''Virgil.UI.csproj''
$svcDir = Join-Path $ui ''Services''
$svcMon = Join-Path $svcDir ''MonitoringService.cs''

Write-Host "🔧 Patch monitoring (WMI + System.Management)..." -ForegroundColor Yellow
if(-not (Test-Path $csproj)){ throw "csproj introuvable: $csproj" }
New-Item -ItemType Directory -Force -Path $svcDir | Out-Null

# 1) Ajoute le package System.Management si absent
$needPkg = -not (Select-String -Path $csproj -SimpleMatch ''<PackageReference Include="System.Management"'' -ErrorAction SilentlyContinue)
if($needPkg){
  Write-Host "➕ dotnet add package System.Management" -ForegroundColor Cyan
  Push-Location $ui
  dotnet add package System.Management --version 8.0.0
  Pop-Location
}else{
  Write-Host "ℹ️ System.Management déjà référencé" -ForegroundColor DarkGray
}

# 2) Réécrit MonitoringService.cs
@"
using System;
using System.ComponentModel;
using System.Linq;
using System.Timers;
using System.Management;

namespace Virgil.UI.Services
{
    public sealed class MonitoringService : INotifyPropertyChanged, IDisposable
    {
        private readonly Timer _timer;
        private bool _enabled;
        private double _cpu;
        private double _mem;

        public double CpuUsage
        {
            get => _cpu;
            private set { if (Math.Abs(_cpu - value) > 0.05) { _cpu = value; OnPropertyChanged(nameof(CpuUsage)); } }
        }

        public double MemoryUsage
        {
            get => _mem;
            private set { if (Math.Abs(_mem - value) > 0.05) { _mem = value; OnPropertyChanged(nameof(MemoryUsage)); } }
        }

        public bool Enabled
        {
            get => _enabled;
            set
            {
                if (_enabled == value) return;
                _enabled = value;
                if (_enabled) _timer.Start(); else _timer.Stop();
                OnPropertyChanged(nameof(Enabled));
            }
        }

        public MonitoringService(int intervalMs = 2000)
        {
            _timer = new Timer(intervalMs) { AutoReset = true };
            _timer.Elapsed += OnTick;
        }

        private void OnTick(object? sender, ElapsedEventArgs e)
        {
            try
            {
                using (var cpuQ = new ManagementObjectSearcher("select LoadPercentage from Win32_Processor"))
                {
                    var vals = cpuQ.Get().Cast<ManagementObject>()
                                   .Select(mo => Convert.ToDouble(mo["LoadPercentage"]))
                                   .ToArray();
                    if (vals.Length > 0)
                        CpuUsage = Math.Round(vals.Average(), 1);
                }

                using (var osQ = new ManagementObjectSearcher("select FreePhysicalMemory, TotalVisibleMemorySize from Win32_OperatingSystem"))
                {
                    var os = osQ.Get().Cast<ManagementObject>().FirstOrDefault();
                    if (os != null)
                    {
                        double freeKB = Convert.ToDouble(os["FreePhysicalMemory"]);
                        double totalKB = Convert.ToDouble(os["TotalVisibleMemorySize"]);
                        if (totalKB > 0)
                        {
                            double usedPerc = (1.0 - (freeKB / totalKB)) * 100.0;
                            MemoryUsage = Math.Round(usedPerc, 1);
                        }
                    }
                }
            }
            catch { /* on ignore les erreurs ponctuelles */ }
        }

        public void Dispose()
        {
            _timer.Elapsed -= OnTick;
            _timer.Dispose();
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
"@ | Set-Content -Encoding UTF8 $svcMon

Write-Host "✅ MonitoringService.cs réécrit → $svcMon" -ForegroundColor Green

Write-Host "`n🧪 Build..." -ForegroundColor Yellow
dotnet build $csproj -c Release
if ($LASTEXITCODE -ne 0) { throw "Build échoué" }
Write-Host "✅ Build OK" -ForegroundColor Green
