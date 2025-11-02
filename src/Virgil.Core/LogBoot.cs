using Serilog;
namespace Virgil.Core;
public static class LogBoot {
  public static void Init(){
    var dir = System.IO.Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.CommonApplicationData), "Virgil", "logs");
    System.IO.Directory.CreateDirectory(dir);
    var path = System.IO.Path.Combine(dir, $"{System.DateTime.Now:yyyy-MM-dd}.log");
    Log.Logger = new LoggerConfiguration().MinimumLevel.Debug()
      .WriteTo.File(path, rollingInterval: RollingInterval.Day, retainedFileCountLimit:30)
      .WriteTo.Console().CreateLogger();
    Log.Information("=== Virgil ready ===");
  }
}
