namespace P2PFile.Runtime;

public sealed class P2PFileRuntimeHostOptions
{
    public string DisplayName { get; set; } = "P2P File Service";

    public string ShareRoot { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
        "P2PFileShare");

    public int Port { get; set; } = 48888;

    public string ServiceName { get; set; } = "p2p-file-service";

    public string ServiceType { get; set; } = "_p2pfiles._tcp";

    public string Domain { get; set; } = "local.";

    public string PairingUriScheme { get; set; } = "p2pfiles";

    public string StateRoot { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "P2PFileService");

    public string ControlPipeName { get; set; } = "P2PFileServiceControl";

    public string CertificateSubjectName { get; set; } = "CN=P2PFileService";

    public P2PFileRuntimeHostOptions Clone()
    {
        return new P2PFileRuntimeHostOptions
        {
            DisplayName = DisplayName,
            ShareRoot = ShareRoot,
            Port = Port,
            ServiceName = ServiceName,
            ServiceType = ServiceType,
            Domain = Domain,
            PairingUriScheme = PairingUriScheme,
            StateRoot = StateRoot,
            ControlPipeName = ControlPipeName,
            CertificateSubjectName = CertificateSubjectName,
        };
    }
}
