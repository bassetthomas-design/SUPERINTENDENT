using System;
using System.Globalization;
using System.Windows.Data;

namespace Virgil.UI.Controls
{
    public sealed class BooleanToOnOffConverter : IValueConverter
    {
        public static readonly BooleanToOnOffConverter Instance = new BooleanToOnOffConverter();

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            bool b = value is bool v && v;
            string prefix = parameter as string ?? "Surveillance";
            return b ? $"{prefix} : ON" : $"{prefix} : OFF";
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => throw new NotImplementedException();
    }
}
