using P2PFile.Infrastructure;
using P2PFile.Protocol;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace P2PFile.Runtime;

public sealed class TransferServer
{
    private readonly ILogger<TransferServer> _logger;
    private readonly ServiceConfigurationStore _configurationStore;
    private readonly TrustedDeviceRegistry _trustedDeviceRegistry;
    private readonly ShareRootValidator _shareRootValidator;
    private readonly ManifestBuilder _manifestBuilder;
    private readonly PairingTokenManager _pairingTokenManager;
    private readonly ServiceStatusStore _statusStore;
    private readonly ServerCertificateProvider _certificateProvider;
    private readonly BonjourAdvertiser _bonjourAdvertiser;
    private readonly P2PFileRuntimeHostOptions _options;
    private int _activePort;

    public TransferServer(
        ILogger<TransferServer> logger,
        ServiceConfigurationStore configurationStore,
        TrustedDeviceRegistry trustedDeviceRegistry,
        ShareRootValidator shareRootValidator,
        ManifestBuilder manifestBuilder,
        PairingTokenManager pairingTokenManager,
        ServiceStatusStore statusStore,
        ServerCertificateProvider certificateProvider,
        BonjourAdvertiser bonjourAdvertiser,
        P2PFileRuntimeHostOptions options)
    {
        _logger = logger;
        _configurationStore = configurationStore;
        _trustedDeviceRegistry = trustedDeviceRegistry;
        _shareRootValidator = shareRootValidator;
        _manifestBuilder = manifestBuilder;
        _pairingTokenManager = pairingTokenManager;
        _statusStore = statusStore;
        _certificateProvider = certificateProvider;
        _bonjourAdvertiser = bonjourAdvertiser;
        _options = options;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        var configuration = await _configurationStore.LoadAsync(cancellationToken);
        _activePort = configuration.Port;
        var certificate = _certificateProvider.LoadOrCreate();
        _shareRootValidator.ValidateShareRoot(configuration.ShareRoot);
        await RefreshActivePairingPayloadAsync(cancellationToken);

        using var listener = new TcpListener(IPAddress.Any, configuration.Port);
        listener.Start();

        var controlPipeServer = new ControlPipeServer(_options.ControlPipeName, HandleControlRequestAsync);
        var controlTask = Task.Run(() => controlPipeServer.RunAsync(cancellationToken), cancellationToken);

        try
        {
            try
            {
                _bonjourAdvertiser.Start(configuration);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Bonjour/mDNS advertisement could not be started. The local runtime will continue without discovery.");
            }

            while (!cancellationToken.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(cancellationToken);
                _ = Task.Run(() => HandleClientAsync(client, certificate, cancellationToken), cancellationToken);
            }
        }
        finally
        {
            listener.Stop();
            _bonjourAdvertiser.Stop();
            await controlTask;
        }
    }

    private async Task HandleClientAsync(TcpClient client, X509Certificate2 certificate, CancellationToken cancellationToken)
    {
        using var _ = client;
        using var sslStream = new SslStream(client.GetStream(), leaveInnerStreamOpen: false);

        try
        {
            await sslStream.AuthenticateAsServerAsync(new SslServerAuthenticationOptions
            {
                ServerCertificate = certificate,
                EnabledSslProtocols = System.Security.Authentication.SslProtocols.Tls12 | System.Security.Authentication.SslProtocols.Tls13,
                CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
                ClientCertificateRequired = false,
            }, cancellationToken);

            var configuration = await _configurationStore.LoadAsync(cancellationToken);
            var hello = await FrameCodec.ReadJsonAsync<HelloRequest>(sslStream, WireMessageType.Hello, cancellationToken);
            _logger.LogInformation("Accepted transport hello from {DisplayName} ({DeviceId}).", hello.DisplayName, hello.DeviceId);

            var challenge = RandomNumberGenerator.GetBytes(32);
            await FrameCodec.WriteJsonAsync(
                sslStream,
                WireMessageType.HelloAck,
                new HelloResponse(
                    ServiceDiscoveryMetadata.ProtocolVersion,
                    GuidUtility.FromDeterministicName(configuration.ServiceName),
                    configuration.DisplayName,
                    ServiceDiscoveryMetadata.Capabilities,
                    challenge),
                cancellationToken: cancellationToken);

            var handshakeFrame = await FrameCodec.ReadAsync(sslStream, cancellationToken);
            var identity = handshakeFrame.Type switch
            {
                WireMessageType.PairRequest => await HandlePairingAsync(handshakeFrame, challenge, configuration, sslStream, cancellationToken),
                WireMessageType.AuthenticateRequest => await HandleAuthenticationAsync(handshakeFrame, challenge, sslStream, cancellationToken),
                _ => throw new InvalidDataException($"Unexpected handshake frame type {handshakeFrame.Type}."),
            };

            while (!cancellationToken.IsCancellationRequested)
            {
                var frame = await FrameCodec.ReadAsync(sslStream, cancellationToken);
                switch (frame.Type)
                {
                    case WireMessageType.ManifestRequest:
                        await HandleManifestRequestAsync(identity, configuration, sslStream, cancellationToken);
                        break;
                    case WireMessageType.FileRequest:
                        await HandleFileRequestAsync(identity, configuration, Deserialize<FileRequest>(frame.Metadata), sslStream, cancellationToken);
                        break;
                    case WireMessageType.CancelTransfer:
                        return;
                    case WireMessageType.Keepalive:
                        await FrameCodec.WriteJsonAsync(sslStream, WireMessageType.Keepalive, new { ok = true }, cancellationToken: cancellationToken);
                        break;
                    default:
                        throw new InvalidDataException($"Unsupported request type {frame.Type}.");
                }
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "A client session failed.");
            try
            {
                await FrameCodec.WriteJsonAsync(
                    sslStream,
                    WireMessageType.Error,
                    new ErrorMetadata("session_failed", ex.Message),
                    cancellationToken: cancellationToken);
            }
            catch
            {
            }
        }
    }

    private async Task<ClientIdentity> HandlePairingAsync(
        FrameEnvelope frame,
        byte[] challenge,
        ServiceConfiguration configuration,
        Stream stream,
        CancellationToken cancellationToken)
    {
        var request = Deserialize<PairRequest>(frame.Metadata);
        VerifyClientSignature(request.ClientPublicKey, challenge, request.ChallengeSignature);
        if (!_pairingTokenManager.TryUseToken(request.PairingToken))
        {
            throw new InvalidOperationException("The pairing token is invalid or expired.");
        }

        var trustedDevice = new TrustedDevice(
            request.ClientDeviceId,
            request.ClientDisplayName,
            Convert.ToBase64String(request.ClientPublicKey),
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow,
            null,
            false);
        await _trustedDeviceRegistry.UpsertAsync(trustedDevice, cancellationToken);

        await FrameCodec.WriteJsonAsync(
            stream,
            WireMessageType.PairResponse,
            new PairResponse(
                GuidUtility.FromDeterministicName(configuration.ServiceName),
                configuration.DisplayName,
                ServiceDiscoveryMetadata.Capabilities),
            cancellationToken: cancellationToken);
        await RefreshActivePairingPayloadAsync(cancellationToken);

        return new ClientIdentity(trustedDevice.DeviceId, trustedDevice.DisplayName);
    }

    private async Task<ClientIdentity> HandleAuthenticationAsync(
        FrameEnvelope frame,
        byte[] challenge,
        Stream stream,
        CancellationToken cancellationToken)
    {
        var request = Deserialize<AuthenticateRequest>(frame.Metadata);
        var trustedDevice = await _trustedDeviceRegistry.FindAsync(request.ClientDeviceId, cancellationToken)
            ?? throw new InvalidOperationException("The device is not trusted.");
        if (trustedDevice.Revoked)
        {
            await FrameCodec.WriteJsonAsync(stream, WireMessageType.AuthenticateResponse, new AuthenticateResponse(false, true), cancellationToken: cancellationToken);
            throw new InvalidOperationException("The device has been revoked.");
        }

        VerifyClientSignature(Convert.FromBase64String(trustedDevice.PublicKeyBase64), challenge, request.ChallengeSignature);
        await _trustedDeviceRegistry.UpsertAsync(trustedDevice with { LastConnectedAt = DateTimeOffset.UtcNow }, cancellationToken);
        await FrameCodec.WriteJsonAsync(stream, WireMessageType.AuthenticateResponse, new AuthenticateResponse(true, false), cancellationToken: cancellationToken);
        return new ClientIdentity(trustedDevice.DeviceId, trustedDevice.DisplayName);
    }

    private async Task HandleManifestRequestAsync(
        ClientIdentity identity,
        ServiceConfiguration configuration,
        Stream stream,
        CancellationToken cancellationToken)
    {
        var manifest = await _manifestBuilder.BuildAsync(GuidUtility.FromDeterministicName(configuration.ServiceName), configuration.ShareRoot, cancellationToken);
        _logger.LogInformation("Manifest requested by {DeviceId}; {Count} file(s) available.", identity.DeviceId, manifest.Files.Count);
        await FrameCodec.WriteJsonAsync(stream, WireMessageType.ManifestResponse, manifest, cancellationToken: cancellationToken);
    }

    private async Task HandleFileRequestAsync(
        ClientIdentity identity,
        ServiceConfiguration configuration,
        FileRequest request,
        Stream stream,
        CancellationToken cancellationToken)
    {
        var absolutePath = _shareRootValidator.ResolveRelativePath(configuration.ShareRoot, request.FileId);
        if (!File.Exists(absolutePath))
        {
            throw new FileNotFoundException("The requested file does not exist.", request.FileId);
        }

        var info = new FileInfo(absolutePath);
        var relativePath = Path.GetRelativePath(configuration.ShareRoot, absolutePath).Replace('\\', '/');
        var hash = await ComputeFileHashAsync(absolutePath, cancellationToken);
        await using var fileStream = File.Open(absolutePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);

        var buffer = new byte[64 * 1024];
        var chunkIndex = 0;
        long totalTransferred = 0;

        while (true)
        {
            var bytesRead = await fileStream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
            if (bytesRead == 0)
            {
                break;
            }

            totalTransferred += bytesRead;
            await FrameCodec.WriteJsonAsync(
                stream,
                WireMessageType.FileChunk,
                new FileChunkMetadata(relativePath.ToLowerInvariant(), chunkIndex++, bytesRead, info.Length),
                buffer.AsMemory(0, bytesRead),
                cancellationToken);
        }

        await FrameCodec.WriteJsonAsync(
            stream,
            WireMessageType.TransferComplete,
            new TransferCompleteMetadata(relativePath.ToLowerInvariant(), info.Length, hash),
            cancellationToken: cancellationToken);

        await _statusStore.AddTransferAsync(
            new TransferActivity(identity.DeviceId, identity.DisplayName, relativePath, info.Length, DateTimeOffset.UtcNow),
            cancellationToken);

        var trustedDevice = await _trustedDeviceRegistry.FindAsync(identity.DeviceId, cancellationToken);
        if (trustedDevice is not null)
        {
            await _trustedDeviceRegistry.UpsertAsync(trustedDevice with { LastTransferAt = DateTimeOffset.UtcNow }, cancellationToken);
        }

        _logger.LogInformation("Transferred {RelativePath} to {DisplayName} ({Bytes} bytes).", relativePath, identity.DisplayName, totalTransferred);
    }

    private async Task<ControlResponse> HandleControlRequestAsync(ControlRequest request, CancellationToken cancellationToken)
    {
        try
        {
            return request.Command switch
            {
                ControlCommandType.GetSnapshot => new ControlResponse(true, null, await BuildSnapshotAsync(cancellationToken)),
                ControlCommandType.UpdateShareRoot => await UpdateShareRootAsync(request, cancellationToken),
                ControlCommandType.UpdateServiceSettings => await UpdateServiceSettingsAsync(request, cancellationToken),
                ControlCommandType.RevokeDevice => await RevokeDeviceAsync(request, cancellationToken),
                _ => new ControlResponse(false, "Unknown control command."),
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Control command {Command} failed.", request.Command);
            return new ControlResponse(false, ex.Message);
        }
    }

    private async Task<ControlResponse> UpdateShareRootAsync(ControlRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.ShareRoot))
        {
            return new ControlResponse(false, "A share root path is required.");
        }

        await _configurationStore.UpdateShareRootAsync(request.ShareRoot, _shareRootValidator, cancellationToken);
        return new ControlResponse(true, null, await BuildSnapshotAsync(cancellationToken));
    }

    private async Task<ControlResponse> UpdateServiceSettingsAsync(ControlRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.DisplayName))
        {
            return new ControlResponse(false, "A display name is required.");
        }

        if (request.Port is null)
        {
            return new ControlResponse(false, "A port is required.");
        }

        if (string.IsNullOrWhiteSpace(request.ServiceType))
        {
            return new ControlResponse(false, "A service type is required.");
        }

        if (string.IsNullOrWhiteSpace(request.PairingUriScheme))
        {
            return new ControlResponse(false, "A pairing URI scheme is required.");
        }

        await _configurationStore.UpdateServiceSettingsAsync(
            request.DisplayName,
            request.Port.Value,
            request.ServiceType,
            request.PairingUriScheme,
            cancellationToken);
        await RefreshActivePairingPayloadAsync(cancellationToken);
        await RefreshBonjourAdvertisementAsync(cancellationToken);
        return new ControlResponse(true, null, await BuildSnapshotAsync(cancellationToken));
    }

    private async Task<ControlResponse> RevokeDeviceAsync(ControlRequest request, CancellationToken cancellationToken)
    {
        if (request.DeviceId is null)
        {
            return new ControlResponse(false, "A device identifier is required.");
        }

        await _trustedDeviceRegistry.RevokeAsync(request.DeviceId.Value, cancellationToken);
        return new ControlResponse(true, null, await BuildSnapshotAsync(cancellationToken));
    }

    private async Task<ServiceStatusSnapshot> BuildSnapshotAsync(CancellationToken cancellationToken)
    {
        await EnsureActivePairingPayloadAsync(cancellationToken);
        var configuration = await _configurationStore.LoadAsync(cancellationToken);
        var devices = await _trustedDeviceRegistry.LoadAsync(cancellationToken);
        return await _statusStore.SnapshotAsync(configuration, _activePort, devices, cancellationToken);
    }

    private async Task<PairingPayload> EnsureActivePairingPayloadAsync(CancellationToken cancellationToken)
    {
        var payload = await _statusStore.GetActivePairingPayloadAsync(cancellationToken);
        if (payload is not null && payload.ExpiresAt > DateTimeOffset.UtcNow)
        {
            return payload;
        }

        return await RefreshActivePairingPayloadAsync(cancellationToken);
    }

    private async Task<PairingPayload> RefreshActivePairingPayloadAsync(CancellationToken cancellationToken)
    {
        var payload = await _pairingTokenManager.CreatePayloadAsync(cancellationToken);
        await _statusStore.SetActivePairingPayloadAsync(payload, cancellationToken);
        return payload;
    }

    private async Task RefreshBonjourAdvertisementAsync(CancellationToken cancellationToken)
    {
        var configuration = await _configurationStore.LoadAsync(cancellationToken);

        try
        {
            _bonjourAdvertiser.Start(configuration with { Port = _activePort });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Bonjour/mDNS advertisement could not be refreshed after the service settings changed.");
        }
    }

    private static T Deserialize<T>(byte[] data)
    {
        return JsonSerializer.Deserialize<T>(data, ProtocolJson.Options)
            ?? throw new InvalidDataException($"Unable to deserialize {typeof(T).Name}.");
    }

    private static async Task<string> ComputeFileHashAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken)).ToLowerInvariant();
    }

    private static void VerifyClientSignature(byte[] publicKeyBytes, byte[] challenge, byte[] signature)
    {
        var normalizedPublicKey = NormalizeClientPublicKey(publicKeyBytes);

        using var ecdsa = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint
            {
                X = normalizedPublicKey[1..33],
                Y = normalizedPublicKey[33..65],
            },
        });

        if (!ecdsa.VerifyData(challenge, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
        {
            throw new InvalidOperationException("The client signature did not match the challenge.");
        }
    }

    private static byte[] NormalizeClientPublicKey(byte[] publicKeyBytes)
    {
        if (publicKeyBytes.Length == 65 && publicKeyBytes[0] == 0x04)
        {
            return publicKeyBytes;
        }

        if (publicKeyBytes.Length == 64)
        {
            return [0x04, .. publicKeyBytes];
        }

        throw new InvalidOperationException("The client public key format was invalid.");
    }

    private sealed record ClientIdentity(Guid DeviceId, string DisplayName);
}
