using P2PFile.Protocol;

namespace P2PFile.Tests;

public sealed class FrameCodecTests
{
    [Fact]
    public async Task RoundTripsFramePayload()
    {
        await using var stream = new MemoryStream();
        var manifest = new RemoteFileManifest(Guid.NewGuid(), DateTimeOffset.UtcNow, []);

        await FrameCodec.WriteJsonAsync(stream, WireMessageType.ManifestResponse, manifest);
        stream.Position = 0;

        var frame = await FrameCodec.ReadAsync(stream);
        Assert.Equal(WireMessageType.ManifestResponse, frame.Type);
        var decoded = System.Text.Json.JsonSerializer.Deserialize<RemoteFileManifest>(frame.Metadata, ProtocolJson.Options);
        Assert.NotNull(decoded);
        Assert.Equal(manifest.DeviceId, decoded!.DeviceId);
    }
}
