using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Virgil.UI.ViewModels
{
    public static class ActivityDetector
    {
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        // Map rapide: process -> catégorie
        private static readonly Dictionary<string,string> _map = new(StringComparer.OrdinalIgnoreCase)
        {
            // Jeux (ajoute ceux que tu utilises)
            ["bf2042"] = "Gaming",
            ["valorant"] = "Gaming",
            ["cs2"] = "Gaming",
            ["steam"] = "Gaming",
            // Navigateurs
            ["chrome"] = "Browsing",
            ["msedge"] = "Browsing",
            ["firefox"] = "Browsing",
            ["opera"] = "Browsing",
            // Bureautique
            ["code"] = "Working",      // VS Code
            ["devenv"] = "Working",    // Visual Studio
            ["excel"] = "Working",
            ["winword"] = "Working",
            ["powerpnt"] = "Working"
        };

        public static string GetCurrentCategory()
        {
            try
            {
                var h = GetForegroundWindow();
                if (h == IntPtr.Zero) return "Idle";
                GetWindowThreadProcessId(h, out var pid);
                using var p = Process.GetProcessById((int)pid);
                var name = (p?.ProcessName ?? "").ToLowerInvariant();
                if (_map.TryGetValue(name, out var cat)) return cat;
                return "Idle";
            }
            catch { return "Idle"; }
        }
    }
}
