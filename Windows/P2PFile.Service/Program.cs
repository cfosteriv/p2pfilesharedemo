using P2PFile.Runtime;

var builder = Host.CreateApplicationBuilder(args);
P2PFileRuntimeBootstrap.Configure(builder, P2PFileReferenceRuntimeHost.Create());

await builder.Build().RunAsync();
