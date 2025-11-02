namespace Virgil.Core
{
    // Alias compatible avec l'Agent (même signature que CommandResult)
    public readonly record struct CommandResponse(bool Success, CommandType Kind, string Message);
}
