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
            logger.LogInformation("negotiating new connection.");
            return Negotiate(req.Headers["x-ms-signalr-user-id"]);
        }

        [FunctionName(nameof(OnConnected))]
        public async Task OnConnected([SignalRTrigger]InvocationContext invocationContext, ILogger logger)
        {
            await Clients.All.SendAsync("newConnection", invocationContext.ConnectionId);
            logger.LogInformation($"{invocationContext.ConnectionId} has connected");
        }

        [FunctionName(nameof(Broadcast))]
        public async Task Broadcast([SignalRTrigger]InvocationContext invocationContext, string message, ILogger logger)
        {
            await Clients.All.SendAsync("newMessage", $"{invocationContext.ConnectionId} broadcast {message}");
            logger.LogInformation($"{invocationContext.ConnectionId} broadcast {message}");
        }

        [FunctionName(nameof(OnDisconnected))]
        public void OnDisconnected([SignalRTrigger]InvocationContext invocationContext)
        {
        }
    }
}
