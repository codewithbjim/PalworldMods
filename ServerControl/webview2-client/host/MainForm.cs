using System.Text.Json;
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace PalworldServerControl.Host;

internal sealed class MainForm : Form
{
    private const string AppOrigin = "https://palworld-control.local";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly WebView2 _webView = new() { Dock = DockStyle.Fill, AllowExternalDrop = false };
    private readonly HostOptions _options;
    private readonly ConnectionManager _connections;
    private PalworldService _service;
    private string _shareRoot;
    private readonly SemaphoreSlim _bridgeGate = new(1, 1);

    internal MainForm(HostOptions options)
    {
        _options = options;
        _connections = new ConnectionManager(options.ShareRoot);
        _shareRoot = _connections.ResolveInitialRoot();
        _service = CreateService(_shareRoot);
        Text = "Palworld Server Control";
        Width = 1540;
        Height = 1020;
        MinimumSize = new Size(1120, 720);
        BackColor = Color.FromArgb(248, 250, 252);
        StartPosition = FormStartPosition.CenterScreen;
        var executablePath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(executablePath))
            Icon = Icon.ExtractAssociatedIcon(executablePath);
        Controls.Add(_webView);
        Shown += async (_, _) => await InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            var userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "virtualbjorn", "PalworldServerControl", "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: userData);
            await _webView.EnsureCoreWebView2Async(environment);
            var core = _webView.CoreWebView2;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.AreHostObjectsAllowed = false;
            core.SetVirtualHostNameToFolderMapping(
                "palworld-control.local",
                Path.Combine(AppContext.BaseDirectory, "wwwroot"),
                CoreWebView2HostResourceAccessKind.DenyCors);
            core.WebMessageReceived += OnWebMessageReceived;
            core.NewWindowRequested += (_, eventArgs) => eventArgs.Handled = true;
            core.PermissionRequested += (_, eventArgs) => eventArgs.State = CoreWebView2PermissionState.Deny;
            core.NavigationStarting += (_, eventArgs) =>
            {
                if (!eventArgs.Uri.StartsWith(AppOrigin + "/", StringComparison.OrdinalIgnoreCase))
                    eventArgs.Cancel = true;
            };
            Task? navigation = null;
            if (_options.ScreenshotPath is not null)
            {
                navigation = WaitForDocumentAsync();
            }
            core.Navigate(AppOrigin + "/index.html");

            if (_options.ScreenshotPath is not null)
            {
                await navigation!;
                await Task.Delay(2500);
                Directory.CreateDirectory(Path.GetDirectoryName(_options.ScreenshotPath)!);
                await using var stream = File.Create(_options.ScreenshotPath);
                await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
                Close();
            }
        }
        catch (WebView2RuntimeNotFoundException)
        {
            ShowFatal("Microsoft Edge WebView2 Runtime is required. Install the Evergreen Runtime and try again.");
        }
        catch (Exception exception)
        {
            ShowFatal(exception.Message);
        }
    }

    private async Task WaitForDocumentAsync()
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnCompleted(object? _, CoreWebView2NavigationCompletedEventArgs args)
        {
            if (args.IsSuccess) completion.TrySetResult();
            else completion.TrySetException(new InvalidOperationException($"Web UI failed to load ({args.WebErrorStatus})."));
        }
        _webView.CoreWebView2.NavigationCompleted += OnCompleted;
        try { await completion.Task.WaitAsync(TimeSpan.FromSeconds(30)); }
        finally { _webView.CoreWebView2.NavigationCompleted -= OnCompleted; }
    }

    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs eventArgs)
    {
        BridgeRequest? request = null;
        try
        {
            if (!string.Equals(eventArgs.Source, AppOrigin + "/", StringComparison.OrdinalIgnoreCase) &&
                !eventArgs.Source.StartsWith(AppOrigin + "/", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Messages are accepted only from the packaged application.");
            request = JsonSerializer.Deserialize<BridgeRequest>(eventArgs.WebMessageAsJson, JsonOptions)
                ?? throw new InvalidOperationException("Invalid bridge request.");
            if (string.IsNullOrWhiteSpace(request.Id) || request.Id.Length > 128)
                throw new InvalidOperationException("Invalid bridge request id.");

            await _bridgeGate.WaitAsync();
            object result;
            try
            {
                result = request.Method switch
                {
                    "snapshot.load" when request.Params.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                        => await _service.LoadSnapshotAsync(),
                    "settings.save" => await _service.SaveSettingsAsync(request.Params.Deserialize<SaveRequest>(JsonOptions)
                        ?? throw new InvalidOperationException("Invalid save request.")),
                    "command.send" => await _service.SendCommandAsync(request.Params.Deserialize<CommandRequest>(JsonOptions)
                        ?? throw new InvalidOperationException("Invalid command request.")),
                    "connection.current" when request.Params.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                        => _connections.InspectCurrent(_shareRoot),
                    "connection.detect" when request.Params.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                        => DetectConnection(),
                    "connection.choose" when request.Params.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                        => ChooseConnection(),
                    "connection.test" => TestConnection(request.Params.Deserialize<ConnectionRequest>(JsonOptions)
                        ?? throw new InvalidOperationException("Invalid connection request.")),
                    "connection.save" => SaveConnection(request.Params.Deserialize<ConnectionRequest>(JsonOptions)
                        ?? throw new InvalidOperationException("Invalid connection request.")),
                    "helper.status" when request.Params.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                        => GetHelperState(),
                    "helper.install" when request.Params.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                        => await InstallHelperAsync(),
                    _ => throw new InvalidOperationException("Unsupported bridge method.")
                };
            }
            finally { _bridgeGate.Release(); }
            Post(new BridgeResponse(request.Id, true, result, null));
        }
        catch (Exception exception)
        {
            Post(new BridgeResponse(request?.Id ?? string.Empty, false, null, exception.Message));
        }
    }

    private void Post(BridgeResponse response) =>
        _webView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(response, JsonOptions));

    private PalworldService CreateService(string root) =>
        new(root, Path.Combine(AppContext.BaseDirectory, "metadata"));

    private ConnectionState DetectConnection()
    {
        var detected = _connections.DetectLocalRoot();
        return detected is null
            ? new ConnectionState("", "Detected on this machine", false, "A Palworld server folder could not be detected near this application. Choose the folder manually.")
            : _connections.Inspect(detected, "Detected on this machine");
    }

    private ConnectionState ChooseConnection()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose the Palworld dedicated server folder",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = false
        };
        if (Directory.Exists(_shareRoot)) dialog.InitialDirectory = _shareRoot;
        return dialog.ShowDialog(this) == DialogResult.OK
            ? _connections.Inspect(dialog.SelectedPath, "Selected folder")
            : new ConnectionState("", "Selected folder", false, "Folder selection was cancelled.");
    }

    private ConnectionState TestConnection(ConnectionRequest request) =>
        _connections.Inspect(request.Path, request.Path.TrimStart().StartsWith(@"\\", StringComparison.Ordinal) ? "Network share" : "Selected folder");

    private ConnectionState SaveConnection(ConnectionRequest request)
    {
        var state = TestConnection(request);
        if (!state.Valid) throw new InvalidOperationException(state.Detail);
        if (request.Remember) _connections.Save(state.Path);
        _shareRoot = state.Path;
        _service = CreateService(_shareRoot);
        return request.Remember ? state with { Source = "Remembered" } : state;
    }

    private HelperState GetHelperState()
    {
        if (_shareRoot.StartsWith(@"\\", StringComparison.Ordinal))
            return new(false, false, "The helper can only be installed while this app is running on the physical server with a local server folder selected.");
        var installer = Path.Combine(AppContext.BaseDirectory, "installer", "Install-PalServerControl.ps1");
        var agent = Path.Combine(AppContext.BaseDirectory, "installer", "PalServerControl-Agent.ps1");
        var server = Path.Combine(_shareRoot, "PalServer.exe");
        if (!File.Exists(server)) return new(false, false, "PalServer.exe was not found in the selected local folder.");
        if (!File.Exists(installer) || !File.Exists(agent)) return new(false, false, "The bundled ServerControl installer files could not be loaded.");
        var installedSettings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PalServerControl", "settings.json");
        var installedAgent = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PalServerControl", "PalServerControl-Agent.ps1");
        try
        {
            if (File.Exists(installedSettings) && File.Exists(installedAgent))
            {
                using var document = JsonDocument.Parse(File.ReadAllText(installedSettings));
                if (document.RootElement.TryGetProperty("palServerRoot", out var root) &&
                    string.Equals(Path.GetFullPath(root.GetString() ?? ""), Path.GetFullPath(_shareRoot), StringComparison.OrdinalIgnoreCase))
                    return new(true, true, "The server-control helper is installed for this PalServer folder.");
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { }
        return new(false, true, "The server-control helper is ready to install. Windows will ask for administrator approval.");
    }

    private async Task<HelperState> InstallHelperAsync()
    {
        var before = GetHelperState();
        if (!before.CanInstall) throw new InvalidOperationException(before.Detail);
        var installer = Path.Combine(AppContext.BaseDirectory, "installer", "Install-PalServerControl.ps1");
        var arguments = $"-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File {QuoteArgument(installer)} -PalServerRoot {QuoteArgument(_shareRoot)}";
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = arguments,
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            }) ?? throw new InvalidOperationException("Windows could not start the elevated installer.");
            await process.WaitForExitAsync();
            if (process.ExitCode != 0) throw new InvalidOperationException($"The server-helper installer did not complete successfully (exit code {process.ExitCode}).");
        }
        catch (Win32Exception exception) when (exception.NativeErrorCode == 1223)
        {
            throw new InvalidOperationException("Administrator approval was cancelled.");
        }
        var after = GetHelperState();
        if (!after.Installed) throw new InvalidOperationException("The installer finished, but the installed helper could not be verified.");
        return after with { Detail = "Server helper installed. Restart PalServer once so the REST API setting takes effect." };
    }

    private static string QuoteArgument(string value)
    {
        if (value.Contains('"')) throw new InvalidOperationException("The selected path contains an unsupported quote character.");
        return $"\"{value}\"";
    }

    private void ShowFatal(string message)
    {
        MessageBox.Show(this, message, "Palworld Server Control", MessageBoxButtons.OK, MessageBoxIcon.Error);
        Close();
    }
}
