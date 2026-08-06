namespace PalworldServerControl.Host;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(HostOptions.Parse(args)));
    }
}

internal sealed record HostOptions(string? ShareRoot, string? ScreenshotPath)
{
    internal static HostOptions Parse(string[] args)
    {
        string? shareRoot = null;
        string? screenshot = null;
        foreach (var argument in args)
        {
            if (argument.StartsWith("--share-root=", StringComparison.OrdinalIgnoreCase))
                shareRoot = argument["--share-root=".Length..];
            else if (argument.StartsWith("--screenshot=", StringComparison.OrdinalIgnoreCase))
                screenshot = Path.GetFullPath(argument["--screenshot=".Length..]);
            else
                throw new ArgumentException($"Unsupported argument: {argument}");
        }

        shareRoot ??= Environment.GetEnvironmentVariable("PALSERVER_SHARE_ROOT");
        return new HostOptions(string.IsNullOrWhiteSpace(shareRoot) ? null : shareRoot, screenshot);
    }
}
