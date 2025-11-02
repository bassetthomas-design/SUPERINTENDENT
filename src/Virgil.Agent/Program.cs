using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Virgil.Core;

using Virgil.Agent;
LogBoot.Init(); // boot Serilog tout de suite

var baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Virgil");
Directory.CreateDirectory(Path.Combine(baseDir, "logs"));
Directory.CreateDirectory(Path.Combine(baseDir, "ipc", "commands"));

await Host.CreateDefaultBuilder(args)
    .UseWindowsService(o => o.ServiceName = "VirgilAgent")
    .UseSerilog() // Serilog.Extensions.Hosting (v8/v9) – pas de 'sp' nécessaire
    .ConfigureServices(s =>
    {
        s.AddSingleton<ISensors, SensorManager>();
        s.AddSingleton<ICleaner, CleanerManager>();
        s.AddSingleton<IUpdater, UpdaterManager>();
        s.AddSingleton(new CommandWatcher(baseDir));
        s.AddHostedService<AgentWorker>();
    })
    .Build()
    .RunAsync();


