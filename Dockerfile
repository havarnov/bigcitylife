FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build-env

WORKDIR /app
ADD ./src/bigcitylife /app
RUN dotnet publish -c release -o /out

FROM mcr.microsoft.com/dotnet/aspnet:7.0-alpine

WORKDIR /app

COPY --from=build-env /out .

ENTRYPOINT ["dotnet", "bigcitylife.dll"]

