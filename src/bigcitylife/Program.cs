using Microsoft.AspNetCore.SignalR;
using Microsoft.Azure.Cosmos.Table;
using Microsoft.Azure.Cosmos.Table.Queryable;

var builder = WebApplication.CreateBuilder(args);
builder.Services
    .AddSingleton<IUserIdProvider, UserIdProvider>();
builder.Services
    .AddSignalR()
    .AddJsonProtocol(options => {
        options.PayloadSerializerOptions.PropertyNamingPolicy = null;
    });

builder.Services.AddSingleton(
    p =>
    {
        var configuration = p.GetRequiredService<IConfiguration>();
        return new CloudTable(
            new StorageUri(configuration.GetValue<Uri>("MessageStorage:TableUrl")),
            new StorageCredentials(
                configuration.GetValue<string>("MessageStorage:StorageAccount"),
                configuration.GetValue<string>("MessageStorage:StorageKey")));
    });

var app = builder.Build();

app.MapHub<ChatHub>("/chat");

app.Run();

internal class ChatHub : Hub
{
    private readonly CloudTable _table;
    private readonly ILogger<ChatHub> _logger;

    public ChatHub(
        CloudTable table,
        ILogger<ChatHub> logger)
    {
        _table = table;
        _logger = logger;
    }

    public async Task JoinGroupChat(JoinGroupChatMessage message)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, message.Name);

        // send last message from table storage
        var q = _table.CreateQuery<GroupChatMessageEntity>()
            .Where(x => x.PartitionKey == message.Name)
            .Take(10)
            .AsTableQuery();
        // only fetch first segment, as this is good enough.
        var segment = await _table.ExecuteQuerySegmentedAsync(q, null);
        foreach (var entity in segment.Results.AsEnumerable().Reverse())
        {
            await Clients
                .Client(Context.ConnectionId)
                .SendAsync(
                    "newMessage",
                    entity.UserId,
                    new GroupChatMessage()
                    {
                        ChatName = entity.ChatName,
                        Message = entity.Message,
                    });
        }


        _logger.LogInformation($"{Context.ConnectionId} joined the group chat {message.Name}.");
    }

    public async Task SendToGroupChat(GroupChatMessage message)
    {
        await Clients.Group(message.ChatName).SendAsync("newMessage", Context.UserIdentifier ?? "N/A", message);

        // store to table storage
        await _table.ExecuteAsync(
            TableOperation.InsertOrReplace(
                new GroupChatMessageEntity(
                    message.ChatName,
                    Context.UserIdentifier ?? "N/A",
                    message.Message)));

        _logger.LogInformation($"{Context.ConnectionId} sent group chat message {message.Message} to {message.ChatName}.");
    }
}

internal class JoinGroupChatMessage
{
    public required string Name { get; init; }
}

internal class GroupChatMessage
{
    public required string ChatName { get; init; }

    public required string Message { get; init; }
}

internal class GroupChatMessageEntity : TableEntity
{
    public GroupChatMessageEntity(
        string chatName,
        string userId,
        string message)
    {
        RowKey = $"{DateTime.MaxValue.Ticks - DateTime.UtcNow.Ticks:d19}";
        PartitionKey = chatName;
        UserId = userId;
        Message = message;
    }

    public GroupChatMessageEntity()
    {
    }

    public string ChatName => PartitionKey;

    public string UserId { get; set; } = default!;

    public string Message { get; set; } = default!;
}

internal class UserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection) =>
        connection.GetHttpContext()?.Request.Headers["x-ms-signalr-user-id"];
}


