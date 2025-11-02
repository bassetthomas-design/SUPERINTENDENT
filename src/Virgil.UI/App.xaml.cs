using Virgil.UI.Services;
using System.Windows;
using Virgil.Core;

namespace Virgil.UI
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            LogBoot.Init();
            base.OnStartup(e);
        }
    }
}



