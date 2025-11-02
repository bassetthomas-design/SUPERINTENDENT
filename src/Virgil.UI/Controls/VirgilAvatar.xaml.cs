using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Virgil.UI.Controls
{
    public enum VirgilEmotion { Neutral, Happy, Busy, Warning, Error, IdlePulse }

    public partial class VirgilAvatar : UserControl, INotifyPropertyChanged
    {
        public VirgilAvatar()
        {
            InitializeComponent();
            UpdateVisual();
        }

        public static readonly DependencyProperty EmotionProperty =
            DependencyProperty.Register(nameof(Emotion), typeof(VirgilEmotion), typeof(VirgilAvatar),
                new PropertyMetadata(VirgilEmotion.Neutral, OnEmotionChanged));

        public VirgilEmotion Emotion
        {
            get => (VirgilEmotion)GetValue(EmotionProperty);
            set => SetValue(EmotionProperty, value);
        }

        public static readonly DependencyProperty StatusTextProperty =
            DependencyProperty.Register(nameof(StatusText), typeof(string), typeof(VirgilAvatar),
                new PropertyMetadata("Prêt"));

        public string StatusText
        {
            get => (string)GetValue(StatusTextProperty);
            set => SetValue(StatusTextProperty, value);
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        void OnPropertyChanged([CallerMemberName] string? n = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));

        static void OnEmotionChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is VirgilAvatar v) v.UpdateVisual();
        }

        void UpdateVisual()
        {
            // Sélection couleur d’accent + "bouche" (chemin)
            Brush accent = (Brush)FindResource("Brush.Accent");
            string mouth = "M 30 70 Q 70 90 110 70"; // neutral smile

            switch (Emotion)
            {
                case VirgilEmotion.Neutral:
                    accent = (Brush)FindResource("Brush.Accent");
                    mouth = "M 30 70 Q 70 85 110 70";
                    StatusText = "Prêt";
                    break;

                case VirgilEmotion.Happy:
                    accent = (Brush)FindResource("Brush.AccentHappy");
                    mouth = "M 30 75 Q 70 100 110 75";
                    StatusText = "Heureux de te voir.";
                    break;

                case VirgilEmotion.Busy:
                    accent = (Brush)FindResource("Brush.AccentBusy");
                    mouth = "M 30 70 Q 70 60 110 70";
                    StatusText = "Je travaille…";
                    break;

                case VirgilEmotion.Warning:
                    accent = (Brush)FindResource("Brush.AccentWarn");
                    mouth = "M 35 70 L 105 70";
                    StatusText = "Attention.";
                    break;

                case VirgilEmotion.Error:
                    accent = (Brush)FindResource("Brush.AccentError");
                    mouth = "M 35 80 L 105 60";
                    StatusText = "Oups.";
                    break;

                case VirgilEmotion.IdlePulse:
                    accent = (Brush)FindResource("Brush.Accent");
                    mouth = "M 30 72 Q 70 86 110 72";
                    StatusText = "…";
                    break;
            }

            if (FindName("Mouth") is Path p) p.Data = Geometry.Parse(mouth);
            if (FindName("Core")  is Shape c) c.Stroke = accent;
        }
    }
}