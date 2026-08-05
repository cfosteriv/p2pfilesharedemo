using System.Text.Json;
using P2PFile.Infrastructure;
using P2PFile.Protocol;

namespace P2PFile.Tests;

public sealed class ControlPipeSerializationTests
{
    [Fact]
    public void CompactControlPipeJsonStaysOnOneLineAndRoundTrips()
    {
        var request = new ControlRequest(ControlCommandType.UpdateShareRoot, ShareRoot: @"C:\Users\Test\Documents\P2PFileShare");

        var json = JsonSerializer.Serialize(request, ProtocolJson.CompactOptions);
        var reparsed = JsonSerializer.Deserialize<ControlRequest>(json, ProtocolJson.CompactOptions);

        Assert.DoesNotContain('\n', json);
        Assert.DoesNotContain('\r', json);
        Assert.Equal(request, reparsed);
    }

    [Fact]
    public void CompactControlPipeJsonRoundTripsServiceSettingsUpdates()
    {
        var request = new ControlRequest(
            ControlCommandType.UpdateServiceSettings,
            DisplayName: "Studio Workstation",
            Port: 50001,
            ServiceType: "_contoso-files._tcp",
            PairingUriScheme: "contosofiles");

        var json = JsonSerializer.Serialize(request, ProtocolJson.CompactOptions);
        var reparsed = JsonSerializer.Deserialize<ControlRequest>(json, ProtocolJson.CompactOptions);

        Assert.DoesNotContain('\n', json);
        Assert.DoesNotContain('\r', json);
        Assert.Equal(request, reparsed);
    }
}
