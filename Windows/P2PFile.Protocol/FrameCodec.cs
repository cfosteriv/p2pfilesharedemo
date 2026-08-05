using System.Buffers.Binary;
using System.Text.Json;

namespace P2PFile.Protocol;

public static class FrameCodec
{
    public const int HeaderLength = 10;
    public const int MaximumFrameSize = 8 * 1024 * 1024;

    public static async ValueTask WriteJsonAsync<T>(
        Stream stream,
        WireMessageType type,
        T metadata,
        ReadOnlyMemory<byte> binary = default,
        CancellationToken cancellationToken = default)
    {
        var metadataBytes = JsonSerializer.SerializeToUtf8Bytes(metadata, ProtocolJson.Options);
        await WriteAsync(
            stream,
            new FrameEnvelope(P2PProtocolVersion.V1, type, metadataBytes, binary.ToArray()),
            cancellationToken);
    }

    public static async ValueTask WriteAsync(
        Stream stream,
        FrameEnvelope frame,
        CancellationToken cancellationToken = default)
    {
        var frameLength = 1 + 1 + 4 + frame.Metadata.Length + frame.Binary.Length;
        if (frameLength > MaximumFrameSize)
        {
            throw new InvalidOperationException($"Frame exceeds maximum size of {MaximumFrameSize} bytes.");
        }

        var header = new byte[HeaderLength];
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(0, 4), (uint)frameLength);
        header[4] = (byte)frame.Version;
        header[5] = (byte)frame.Type;
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(6, 4), (uint)frame.Metadata.Length);

        await stream.WriteAsync(header, cancellationToken);
        await stream.WriteAsync(frame.Metadata, cancellationToken);
        if (frame.Binary.Length > 0)
        {
            await stream.WriteAsync(frame.Binary, cancellationToken);
        }
        await stream.FlushAsync(cancellationToken);
    }

    public static async ValueTask<FrameEnvelope> ReadAsync(Stream stream, CancellationToken cancellationToken = default)
    {
        var header = await ReadExactAsync(stream, HeaderLength, cancellationToken);
        var totalLength = (int)BinaryPrimitives.ReadUInt32BigEndian(header.AsSpan(0, 4));
        if (totalLength is < 6 or > MaximumFrameSize)
        {
            throw new InvalidDataException("Invalid frame size.");
        }

        if (!Enum.IsDefined(typeof(P2PProtocolVersion), header[4]))
        {
            throw new InvalidDataException("Unsupported protocol version.");
        }

        if (!Enum.IsDefined(typeof(WireMessageType), header[5]))
        {
            throw new InvalidDataException("Unknown frame type.");
        }

        var metadataLength = (int)BinaryPrimitives.ReadUInt32BigEndian(header.AsSpan(6, 4));
        var remaining = await ReadExactAsync(stream, totalLength - 6, cancellationToken);
        if (metadataLength > remaining.Length)
        {
            throw new InvalidDataException("Frame metadata exceeded payload length.");
        }

        return new FrameEnvelope(
            (P2PProtocolVersion)header[4],
            (WireMessageType)header[5],
            remaining.AsMemory(0, metadataLength).ToArray(),
            remaining.AsMemory(metadataLength).ToArray());
    }

    public static async ValueTask<T> ReadJsonAsync<T>(
        Stream stream,
        WireMessageType expectedType,
        CancellationToken cancellationToken = default)
    {
        var frame = await ReadAsync(stream, cancellationToken);
        if (frame.Type != expectedType)
        {
            throw new InvalidDataException($"Expected {expectedType}, received {frame.Type}.");
        }

        var decoded = JsonSerializer.Deserialize<T>(frame.Metadata, ProtocolJson.Options);
        return decoded ?? throw new InvalidDataException($"Unable to deserialize metadata for {expectedType}.");
    }

    private static async ValueTask<byte[]> ReadExactAsync(Stream stream, int byteCount, CancellationToken cancellationToken)
    {
        var buffer = new byte[byteCount];
        var offset = 0;
        while (offset < byteCount)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(offset, byteCount - offset), cancellationToken);
            if (read == 0)
            {
                throw new EndOfStreamException("The stream ended before the frame was complete.");
            }

            offset += read;
        }

        return buffer;
    }
}
