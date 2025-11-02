using System.Windows;
using System.Windows.Controls;

namespace Virgil.UI.Helpers
{
    public static class PanelSpacing
    {
        public static readonly DependencyProperty SpacingProperty =
            DependencyProperty.RegisterAttached(
                "Spacing",
                typeof(double),
                typeof(PanelSpacing),
                new PropertyMetadata(0d, OnSpacingChanged));

        public static void SetSpacing(DependencyObject element, double value) => element.SetValue(SpacingProperty, value);
        public static double GetSpacing(DependencyObject element) => (double)element.GetValue(SpacingProperty);

        private static void OnSpacingChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is Panel panel)
            {
                // Re-applique quand le layout bouge (simple et robuste)
                panel.Loaded += (_, __) => Apply(panel);
                panel.LayoutUpdated += (_, __) => Apply(panel);
                Apply(panel);
            }
        }

        private static void Apply(Panel panel)
        {
            double spacing = GetSpacing(panel);
            if (spacing <= 0) return;

            // Gère StackPanel vertical/horizontal ; fallback: marge haute
            if (panel is StackPanel sp)
            {
                for (int i = 0; i < sp.Children.Count; i++)
                {
                    if (sp.Children[i] is FrameworkElement fe)
                    {
                        if (sp.Orientation == Orientation.Horizontal)
                            fe.Margin = new Thickness(i == 0 ? 0 : spacing, 0, 0, 0);
                        else
                            fe.Margin = new Thickness(0, i == 0 ? 0 : spacing, 0, 0);
                    }
                }
            }
            else
            {
                // Par défaut: espace vertical entre enfants
                for (int i = 0; i < panel.Children.Count; i++)
                {
                    if (panel.Children[i] is FrameworkElement fe)
                        fe.Margin = new Thickness(0, i == 0 ? 0 : spacing, 0, 0);
                }
            }
        }
    }
}
