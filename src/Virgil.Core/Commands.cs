namespace Virgil.Core
{
    // Types de commandes compris par l'Agent
    public enum CommandType
    {
        Clean = 0,
        UpdateAll = 1,

        // Alias (même valeurs) pour compat UI & scripts existants
        CleanAll = Clean,
        clean    = Clean,
        Update   = UpdateAll,
        update   = UpdateAll
    }

    // Déclaration primaire UNIQUE (partial pour extensions)
    public readonly partial record struct CommandRequest(string Id, CommandType Type);

    // Résultat canon retourné par l'Agent
    public readonly record struct CommandResult(bool Success, CommandType Kind, string Message);
}
