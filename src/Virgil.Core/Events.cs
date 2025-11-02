using System;

namespace Virgil.Core;

public abstract record VirgilEvent(string Kind, DateTime AtUtc, string Message);

public record CleanupStartedEvent(DateTime WhenUtc, string Scope)
  : VirgilEvent("CleanupStarted", WhenUtc, $"Nettoyage démarré ({Scope})");

public record CleanupFinishedEvent(DateTime WhenUtc, long Files, long BytesFreed)
  : VirgilEvent("CleanupFinished", WhenUtc, $"Nettoyage terminé: {Files} fichiers, {BytesFreed/1_000_000d:F1} MB libérés");

public record UpdateStartedEvent(DateTime WhenUtc, string[] Sources)
  : VirgilEvent("UpdateStarted", WhenUtc, $"Mises à jour démarrées ({string.Join(", ", Sources)})");

public record UpdateFinishedEvent(DateTime WhenUtc, int ItemsUpdated)
  : VirgilEvent("UpdateFinished", WhenUtc, $"Mises à jour terminées: {ItemsUpdated} éléments mis à jour");

public record InfoEvent(DateTime WhenUtc, string Text)
  : VirgilEvent("Info", WhenUtc, Text);
