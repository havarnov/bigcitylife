using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs.Extensions.SignalRService;
using Microsoft.Extensions.Logging;

namespace BigCityLife
{
    public class SignalRChatFunction: ServerlessHub
    {
        [FunctionName("negotiate")]
        public SignalRConnectionInfo Negotiate([HttpTrigger(AuthorizationLevel.Anonymous)]HttpRequest req, ILogger logger)
        {
            // TODO: figure out what to do about 'x-ms-signalr-user-id' and JWT bearer
            // return Negotiate(req.Headers["x-ms-signalr-user-id"], GetClaims(req.Headers["Authorization"]));
            return Negotiate();
        }

        [FunctionName(nameof(OnConnected))]
        public async Task OnConnected([SignalRTrigger]InvocationContext invocationContext, ILogger logger)
        {
            logger.LogInformation($"{invocationContext.ConnectionId} has connected.");
            await Task.CompletedTask;
        }

        public class JoinGroupChatMessage
        {
            public string Name { get; set; }
        }

        [FunctionName(nameof(JoinGroupChat))]
        public async Task JoinGroupChat([SignalRTrigger]InvocationContext invocationContext, JoinGroupChatMessage message, ILogger logger)
        {
            await Groups.AddToGroupAsync(invocationContext.UserId, message.Name);
            logger.LogInformation($"{invocationContext.ConnectionId} joined the group chat {message.Name}.");
        }

        public class GroupChatMessage
        {
            public string ChatName { get; set; }

            public string Message { get; set; }
        }

        [FunctionName(nameof(SendToGroupChat))]
        public async Task SendToGroupChat([SignalRTrigger]InvocationContext invocationContext, GroupChatMessage message, ILogger logger)
        {
            await Clients.Group(message.ChatName).SendAsync("newMessage", message.Message);
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
