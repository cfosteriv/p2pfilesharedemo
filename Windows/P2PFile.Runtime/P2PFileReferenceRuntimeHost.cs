namespace P2PFile.Runtime;

public static class P2PFileReferenceRuntimeHost
{
    public const string PairingUriScheme = "p2pfiles";

    public static P2PFileRuntimeHostOptions Create()
    {
        return new P2PFileRuntimeHostOptions
        {
            DisplayName = "P2P File Service",
            ShareRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "P2PFileShare"),
            Port = 48888,
            ServiceName = "p2p-file-service",
            ServiceType = "_p2pfiles._tcp",
            Domain = "local.",
            PairingUriScheme = PairingUriScheme,
            StateRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "P2PFileService"),
            ControlPipeName = "P2PFileServiceControl",
            CertificateSubjectName = "CN=P2PFileService",
        };
    }
}
