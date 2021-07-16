using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Azure.Cosmos.Table;
using Microsoft.Azure.Cosmos.Table.Queryable;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs.Extensions.SignalRService;
using Microsoft.Extensions.Logging;

namespace BigCityLife
{
    public class GroupChatMessageEntity : TableEntity
    {
        public GroupChatMessageEntity(string chatName, string userId, string message)
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

        public string UserId { get; set; }

        public string Message { get; set; }
    }

    public class SignalRChatFunction: ServerlessHub
    {
        private const string MessageTableName = "bigcitylifemessages";

        [FunctionName("testpage")]
        public IActionResult TestPage(
            [HttpTrigger(AuthorizationLevel.Anonymous, Route = "testpage")] HttpRequest request,
            ExecutionContext context)
        {
            var root = context.FunctionAppDirectory;
            return new FileStreamResult(File.OpenRead($"{root}/index.html"), "text/html; charset=UTF-8");
        }

        [FunctionName("negotiate")]
        public SignalRConnectionInfo Negotiate([HttpTrigger(AuthorizationLevel.Anonymous)]HttpRequest req, ILogger logger)
        {
            // TODO: figure out what to do about 'x-ms-signalr-user-id' and JWT bearer
            // return Negotiate(req.Headers["x-ms-signalr-user-id"], GetClaims(req.Headers["Authorization"]));
            if (req.Headers.ContainsKey("x-ms-signalr-user-id"))
            {
                return Negotiate(userId: req.Headers["x-ms-signalr-user-id"]);
            }
            else
            {
                return Negotiate();
            }
        }

        [FunctionName(nameof(OnConnected))]
        public async Task OnConnected(
            [SignalRTrigger]InvocationContext invocationContext,
            ILogger logger)
        {
            logger.LogInformation($"{invocationContext.ConnectionId} has connected.");
            await Task.CompletedTask;
        }

        public class JoinGroupChatMessage
        {
            public string Name { get; set; }
        }

        [FunctionName(nameof(JoinGroupChat))]
        public async Task JoinGroupChat(
            [SignalRTrigger] InvocationContext invocationContext,
            [Table(tableName: MessageTableName)] CloudTable table,
            JoinGroupChatMessage message,
            ILogger logger)
        {
            await Groups.AddToGroupAsync(invocationContext.ConnectionId, message.Name);

            // send last message from table storage
            var q = table.CreateQuery<GroupChatMessageEntity>()
                .Where(x => x.PartitionKey == message.Name)
                .Take(10)
                .AsTableQuery();
            // only fetch first segment, as this is good enough.
            var segment = await table.ExecuteQuerySegmentedAsync(q, null);
            foreach (var entity in segment.Results.AsEnumerable().Reverse())
            {
                await Clients
                    .Client(invocationContext.ConnectionId)
                    .SendAsync(
                        "newMessage",
                        entity.UserId,
                        new GroupChatMessage()
                        {
                            ChatName = entity.ChatName,
                            Message = entity.Message,
                        });
            }


            logger.LogInformation($"{invocationContext.ConnectionId} joined the group chat {message.Name}.");
        }

        public class GroupChatMessage
        {
            public string ChatName { get; set; }

            public string Message { get; set; }
        }

        [FunctionName(nameof(SendToGroupChat))]
        public async Task SendToGroupChat(
            [SignalRTrigger] InvocationContext invocationContext,
            [Table(tableName: MessageTableName)] CloudTable table,
            GroupChatMessage message,
            ILogger logger)
        {
            await Clients.Group(message.ChatName).SendAsync("newMessage", invocationContext.UserId ?? "N/A", message);

            // store to table storage
            await table.ExecuteAsync(
                TableOperation.InsertOrReplace(
                    new GroupChatMessageEntity(
                        message.ChatName,
                        invocationContext.UserId ?? "N/A",
                        message.Message)));

            logger.LogInformation($"{invocationContext.ConnectionId} sent group chat message {message.Message} to {message.ChatName}.");
        }

        [FunctionName(nameof(OnDisconnected))]
        public async Task OnDisconnected([SignalRTrigger]InvocationContext invocationContext, ILogger logger)
        {
            logger.LogInformation($"{invocationContext.ConnectionId} has disconnected.");
            await Task.CompletedTask;
        }
    }
}
