using System.Windows;
using Virgil.UI.ViewModels;

namespace Virgil.UI
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
             this.DataContext = new MainViewModel(); DataContext = new MainViewModel();
        }
    }
}
