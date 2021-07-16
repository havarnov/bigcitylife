# local development

Since we're using serverless signalr there's a couple of moving parts we need to configure to get this up and running.

## local storage emulator

```sh
docker run -it --rm -p 10000:10000 -p 10001:10001 mcr.microsoft.com/azure-storage/azurite
```

## local signalr service emulator

See: https://github.com/Azure/azure-signalr/issues/969

```sh
dotnet new tool-manifest

# find the latest version
# https://www.nuget.org/packages/Microsoft.Azure.SignalR.Emulator
dotnet tool install Microsoft.Azure.SignalR.Emulator --version 1.0.0-preview1-10785

dotnet tool run asrs-emulator upstream init

dotnet tool run asrs-emulator start
# copy the connection string from the output of the previous command
```

## run local function app

From the signalr service emulator copy the connection string into local.settings.json:

```json
	"AzureSignalRConnectionString": "Endpoint=http://localhost;Port=8888;AccessKey=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGH;Version=1.0;",
```

```sh
func start
```
