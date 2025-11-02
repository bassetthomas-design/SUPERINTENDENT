namespace Virgil.Core
{
    public readonly partial record struct CommandRequest
    {
        public CommandRequest(CommandType type, string id) : this(id, type) { }
    }
}
