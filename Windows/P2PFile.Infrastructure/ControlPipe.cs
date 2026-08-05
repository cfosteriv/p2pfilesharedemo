using System.IO.Pipes;
using System.Text.Json;
using P2PFile.Protocol;

namespace P2PFile.Infrastructure;

public sealed class ControlPipeServer
{
    private readonly string _pipeName;
    private readonly Func<ControlRequest, CancellationToken, Task<ControlResponse>> _handler;

    public ControlPipeServer(string pipeName, Func<ControlRequest, CancellationToken, Task<ControlResponse>> handler)
    {
        _pipeName = pipeName;
        _handler = handler;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await using var pipe = new NamedPipeServerStream(_pipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
            await pipe.WaitForConnectionAsync(cancellationToken);

            using var reader = new StreamReader(pipe);
            await using var writer = new StreamWriter(pipe) { AutoFlush = true };
            var line = await reader.ReadLineAsync(cancellationToken);
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var request = JsonSerializer.Deserialize<ControlRequest>(line, ProtocolJson.CompactOptions);
            if (request is null)
            {
                continue;
            }

            var response = await _handler(request, cancellationToken);
            await writer.WriteLineAsync(JsonSerializer.Serialize(response, ProtocolJson.CompactOptions));
        }
    }
}

public sealed class ControlPipeClient
{
    private readonly string _pipeName;

    public ControlPipeClient(string pipeName)
    {
        _pipeName = pipeName;
    }

    public async Task<ControlResponse> SendAsync(ControlRequest request, CancellationToken cancellationToken)
    {
        await using var pipe = new NamedPipeClientStream(".", _pipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
        await pipe.ConnectAsync(cancellationToken);
        using var reader = new StreamReader(pipe);
        await using var writer = new StreamWriter(pipe) { AutoFlush = true };
        await writer.WriteLineAsync(JsonSerializer.Serialize(request, ProtocolJson.CompactOptions));
        var line = await reader.ReadLineAsync(cancellationToken);
        return JsonSerializer.Deserialize<ControlResponse>(line ?? string.Empty, ProtocolJson.CompactOptions)
            ?? new ControlResponse(false, "The service returned an empty control response.");
    }
}
