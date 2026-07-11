using System.Text;
using System.Text.Json;
using Microsoft.Azure.Devices.Client;
using Microsoft.Azure.Devices.Shared;

if (args.Contains("--help", StringComparer.OrdinalIgnoreCase) || args.Contains("-h", StringComparer.OrdinalIgnoreCase))
{
	PrintHelp();
	return;
}

var devicesFile = GetArg(args, "--devices-file") ?? "devices.json";
var quiet = args.Contains("--quiet", StringComparer.OrdinalIgnoreCase);

if (!File.Exists(devicesFile))
{
	Console.Error.WriteLine($"Devices file not found: {devicesFile}");
	Environment.ExitCode = 1;
	return;
}

List<DeviceEntry>? entries;
try
{
	var json = await File.ReadAllTextAsync(devicesFile);
	entries = JsonSerializer.Deserialize<List<DeviceEntry>>(json, new JsonSerializerOptions
	{
		PropertyNameCaseInsensitive = true
	});
}
catch (Exception ex)
{
	Console.Error.WriteLine($"Failed to parse devices file: {ex.Message}");
	Environment.ExitCode = 1;
	return;
}

if (entries is null || entries.Count == 0)
{
	Console.Error.WriteLine("devices.json must contain at least one device entry.");
	Environment.ExitCode = 1;
	return;
}

var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
	eventArgs.Cancel = true;
	cts.Cancel();
};

var runners = entries
	.Where(e => !string.IsNullOrWhiteSpace(e.DeviceId) && !string.IsNullOrWhiteSpace(e.ConnectionString))
	.Select(e => new DeviceRunner(e.DeviceId!, e.ConnectionString!, quiet))
	.ToList();

if (runners.Count == 0)
{
	Console.Error.WriteLine("No valid devices were found in devices.json.");
	Environment.ExitCode = 1;
	return;
}

Console.WriteLine($"Starting {runners.Count} simulator client(s). Press Ctrl+C to stop.");

var tasks = runners.Select(r => r.RunAsync(cts.Token)).ToList();
await Task.WhenAll(tasks);

static string? GetArg(string[] inputArgs, string name)
{
	for (var i = 0; i < inputArgs.Length - 1; i++)
	{
		if (string.Equals(inputArgs[i], name, StringComparison.OrdinalIgnoreCase))
		{
			return inputArgs[i + 1];
		}
	}

	return null;
}

static void PrintHelp()
{
	Console.WriteLine("Usage: dotnet run -- [--devices-file devices.json] [--quiet]");
}

internal sealed class DeviceRunner
{
	private readonly string deviceId;
	private readonly string connectionString;
	private readonly bool quiet;
	private readonly DeviceState state = new();
	private DeviceClient? client;

	public DeviceRunner(string deviceId, string connectionString, bool quiet)
	{
		this.deviceId = deviceId;
		this.connectionString = connectionString;
		this.quiet = quiet;
	}

	public async Task RunAsync(CancellationToken parentToken)
	{
		var reconnectAttempt = 0;
		while (!parentToken.IsCancellationRequested)
		{
			using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(parentToken);
			var token = linkedCts.Token;

			try
			{
				if (reconnectAttempt > 0)
				{
					Log($"reconnect attempt {reconnectAttempt}");
				}

				client = DeviceClient.CreateFromConnectionString(connectionString, TransportType.Mqtt_WebSocket_Only);
				client.SetRetryPolicy(new ExponentialBackoff(retryCount: int.MaxValue, minBackoff: TimeSpan.FromSeconds(1), maxBackoff: TimeSpan.FromSeconds(30), deltaBackoff: TimeSpan.FromSeconds(3)));

				await client.SetMethodDefaultHandlerAsync(OnDefaultMethodAsync, null);
				await client.SetMethodHandlerAsync("setText", OnSetTextAsync, null);
				await client.SetMethodHandlerAsync("getText", OnGetTextAsync, null);
				await client.SetMethodHandlerAsync("setNumber", OnSetNumberAsync, null);
				await client.SetMethodHandlerAsync("getNumber", OnGetNumberAsync, null);
				await client.SetMethodHandlerAsync("startTelemetry", OnStartTelemetryAsync, null);
				await client.SetMethodHandlerAsync("stopTelemetry", OnStopTelemetryAsync, null);
				await client.SetDesiredPropertyUpdateCallbackAsync(OnDesiredPropertiesUpdatedAsync, null);

				// Small jitter helps avoid all devices opening at the exact same moment.
				var jitterMs = Math.Abs(deviceId.GetHashCode()) % 1500;
				await Task.Delay(jitterMs, token);

				Log("opening connection...");
				await client.OpenAsync(token);
				Log("connection opened");

				Log("loading twin...");
				await LoadInitialTwinAsync();

				try
				{
					await ReportStateAsync("connected");
				}
				catch (Exception ex)
				{
					Log($"reported state warning: {ex.Message}");
				}

				Log("connected");
				reconnectAttempt = 0;

				var sendTask = SendTelemetryLoopAsync(token);
				var c2dTask = ReceiveCloudToDeviceLoopAsync(token);
				var duTask = DeviceUpdateIntentLoopAsync(linkedCts, token);

				await Task.WhenAll(sendTask, c2dTask, duTask);
			}
			catch (OperationCanceledException)
			{
				// Expected during shutdown/restart.
			}
			catch (Exception ex)
			{
				reconnectAttempt++;
				Log($"connection error: {ex.Message}");
			}
			finally
			{
				if (client is not null)
				{
					try
					{
						await ReportStateAsync("disconnected");
					}
					catch
					{
						// Ignore report failures during shutdown/reconnect.
					}

					try
					{
						await client.CloseAsync();
					}
					catch
					{
						// Ignore close failures on reconnect.
					}

					client.Dispose();
					client = null;
				}
			}

			if (!parentToken.IsCancellationRequested)
			{
				var backoff = Math.Min(30, Math.Max(2, reconnectAttempt * 2));
				Log($"retrying in {backoff}s...");
				try
				{
					await Task.Delay(TimeSpan.FromSeconds(backoff), parentToken);
				}
				catch (OperationCanceledException)
				{
					// Ignore cancellation during shutdown.
				}
			}
		}
	}

	private async Task SendTelemetryLoopAsync(CancellationToken token)
	{
		while (!token.IsCancellationRequested)
		{
			try
			{
				if (!state.TelemetryEnabled)
				{
					await Task.Delay(TimeSpan.FromSeconds(1), token);
					continue;
				}

				state.SendCount++;
				var isRandomCycle = state.SendCount % state.Config.RandomEvery == 0;
				var temperature = isRandomCycle
					? Random.Shared.NextDouble() * (state.Config.TempMax - state.Config.TempMin) + state.Config.TempMin
					: state.Config.BaseTemp + (Random.Shared.NextDouble() - 0.5);

				var payload = new
				{
					deviceId,
					messageNumber = state.SendCount,
					temperature = Math.Round(temperature, 2),
					temperatureUnit = "C",
					isRandomCycle,
					textValue = state.StoredText,
					numberValue = state.StoredNumber,
					timestampUtc = DateTimeOffset.UtcNow
				};

				var body = JsonSerializer.Serialize(payload);
				var message = new Message(Encoding.UTF8.GetBytes(body))
				{
					ContentType = "application/json",
					ContentEncoding = "utf-8"
				};

				await client!.SendEventAsync(message, token);
				Log($"sent #{state.SendCount}: temp={Math.Round(temperature, 2)} random={isRandomCycle}");
			}
			catch (OperationCanceledException)
			{
				throw;
			}
			catch (Exception ex)
			{
				Log($"send error: {ex.Message}");
			}

			await Task.Delay(TimeSpan.FromSeconds(state.Config.IntervalSeconds), token);
		}
	}

	private async Task ReceiveCloudToDeviceLoopAsync(CancellationToken token)
	{
		while (!token.IsCancellationRequested)
		{
			try
			{
				var message = await client!.ReceiveAsync(token);
				if (message is null)
				{
					continue;
				}

				var body = Encoding.UTF8.GetString(message.GetBytes());
				var enqueuedTime = message.EnqueuedTimeUtc;
				Log($"C2D received: body={body}; enqueuedTimeUtc={enqueuedTime:O}");
				await client.CompleteAsync(message, token);
			}
			catch (OperationCanceledException)
			{
				throw;
			}
			catch (Exception ex)
			{
				Log($"c2d receive error: {ex.Message}");
				await Task.Delay(TimeSpan.FromSeconds(2), token);
			}
		}
	}

	private async Task DeviceUpdateIntentLoopAsync(CancellationTokenSource linkedCts, CancellationToken token)
	{
		while (!token.IsCancellationRequested)
		{
			if (state.RestartRequested)
			{
				await ReportStateAsync("restart-requested");
				Log($"Device Update target version '{state.TargetVersion}' requested. Stopping for external update workflow.");
				linkedCts.Cancel();
				return;
			}

			await Task.Delay(TimeSpan.FromSeconds(2), token);
		}
	}

	private async Task LoadInitialTwinAsync()
	{
		try
		{
			var twin = await client!.GetTwinAsync();
			if (twin.Properties.Desired is not null)
			{
				ApplyDesired(twin.Properties.Desired);
			}
		}
		catch (Exception ex)
		{
			Log($"initial twin warning: {ex.Message}");
		}
	}

	private Task OnDesiredPropertiesUpdatedAsync(TwinCollection desiredProperties, object userContext)
	{
		ApplyDesired(desiredProperties);
		return ReportStateAsync("config-updated");
	}

	private void ApplyDesired(TwinCollection desired)
	{
		if (desired.Contains("sim"))
		{
			var sim = desired["sim"] as TwinCollection;
			if (sim is not null)
			{
				state.Config.IntervalSeconds = ReadDouble(sim, "intervalSeconds", state.Config.IntervalSeconds, min: 0.5);
				state.Config.RandomEvery = (int)ReadDouble(sim, "randomEvery", state.Config.RandomEvery, min: 1);
				state.Config.TempMin = ReadDouble(sim, "tempMin", state.Config.TempMin);
				state.Config.TempMax = ReadDouble(sim, "tempMax", state.Config.TempMax);
				state.Config.BaseTemp = ReadDouble(sim, "baseTemp", state.Config.BaseTemp);
			}
		}

		if (state.Config.TempMin > state.Config.TempMax)
		{
			(state.Config.TempMin, state.Config.TempMax) = (state.Config.TempMax, state.Config.TempMin);
		}

		if (desired.Contains("du"))
		{
			var du = desired["du"] as TwinCollection;
			if (du is not null && du.Contains("targetVersion"))
			{
				var targetVersion = du["targetVersion"]?.ToString();
				if (!string.IsNullOrWhiteSpace(targetVersion) && !string.Equals(targetVersion, AppInfo.Version, StringComparison.OrdinalIgnoreCase))
				{
					state.TargetVersion = targetVersion!;
					state.RestartRequested = true;
				}
			}
		}
	}

	private static double ReadDouble(TwinCollection twin, string key, double defaultValue, double? min = null)
	{
		if (!twin.Contains(key))
		{
			return defaultValue;
		}

		double value;
		if (!double.TryParse(twin[key]?.ToString(), out value))
		{
			return defaultValue;
		}

		if (min.HasValue && value < min.Value)
		{
			value = min.Value;
		}

		return value;
	}

	private Task<MethodResponse> OnSetTextAsync(MethodRequest request, object userContext)
	{
		try
		{
			string? parsed = null;
			if (!string.IsNullOrWhiteSpace(request.DataAsJson))
			{
				using var doc = JsonDocument.Parse(request.DataAsJson);
				if (doc.RootElement.ValueKind == JsonValueKind.Object && doc.RootElement.TryGetProperty("value", out var val))
				{
					parsed = val.GetString();
				}
				else if (doc.RootElement.ValueKind == JsonValueKind.String)
				{
					parsed = doc.RootElement.GetString();
				}
			}

			state.StoredText = parsed ?? string.Empty;
			_ = ReportStateAsync("text-updated");
			Log($"Direct method setText -> '{state.StoredText}'");

			var response = JsonSerializer.Serialize(new { ok = true, storedText = state.StoredText });
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 200));
		}
		catch (Exception ex)
		{
			var response = JsonSerializer.Serialize(new { ok = false, error = ex.Message });
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 400));
		}
	}

	private Task<MethodResponse> OnGetTextAsync(MethodRequest request, object userContext)
	{
		try
		{
			var response = JsonSerializer.Serialize(new
			{
				ok = true,
				storedText = state.StoredText,
				deviceId,
				appVersion = AppInfo.Version
			});

			Log($"Direct method getText -> '{state.StoredText}'");
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 200));
		}
		catch (Exception ex)
		{
			var response = JsonSerializer.Serialize(new { ok = false, error = ex.Message });
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 400));
		}
	}

	private Task<MethodResponse> OnSetNumberAsync(MethodRequest request, object userContext)
	{
		try
		{
			int? parsed = null;
			if (!string.IsNullOrWhiteSpace(request.DataAsJson))
			{
				using var doc = JsonDocument.Parse(request.DataAsJson);
				if (doc.RootElement.ValueKind == JsonValueKind.Object && doc.RootElement.TryGetProperty("value", out var val) && val.TryGetInt32(out var objValue))
				{
					parsed = objValue;
				}
				else if (doc.RootElement.TryGetInt32(out var rootValue))
				{
					parsed = rootValue;
				}
			}

			if (!parsed.HasValue)
			{
				var bad = JsonSerializer.Serialize(new { ok = false, error = "Provide integer payload as {\"value\":123} or raw integer." });
				return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(bad), 400));
			}

			state.StoredNumber = parsed.Value;
			_ = ReportStateAsync("number-updated");
			Log($"Direct method setNumber -> {state.StoredNumber}");

			var response = JsonSerializer.Serialize(new { ok = true, storedNumber = state.StoredNumber });
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 200));
		}
		catch (Exception ex)
		{
			var response = JsonSerializer.Serialize(new { ok = false, error = ex.Message });
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 400));
		}
	}

	private Task<MethodResponse> OnGetNumberAsync(MethodRequest request, object userContext)
	{
		try
		{
			var response = JsonSerializer.Serialize(new
			{
				ok = true,
				storedNumber = state.StoredNumber,
				deviceId,
				appVersion = AppInfo.Version
			});

			Log($"Direct method getNumber -> {state.StoredNumber}");
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 200));
		}
		catch (Exception ex)
		{
			var response = JsonSerializer.Serialize(new { ok = false, error = ex.Message });
			return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 400));
		}
	}

	private Task<MethodResponse> OnStartTelemetryAsync(MethodRequest request, object userContext)
	{
		state.TelemetryEnabled = true;
		_ = ReportStateAsync("telemetry-started");
		Log("Direct method startTelemetry -> telemetry enabled");

		var response = JsonSerializer.Serialize(new
		{
			ok = true,
			telemetryEnabled = state.TelemetryEnabled,
			message = "Telemetry started"
		});

		return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 200));
	}

	private Task<MethodResponse> OnStopTelemetryAsync(MethodRequest request, object userContext)
	{
		state.TelemetryEnabled = false;
		_ = ReportStateAsync("telemetry-stopped");
		Log("Direct method stopTelemetry -> telemetry disabled");

		var response = JsonSerializer.Serialize(new
		{
			ok = true,
			telemetryEnabled = state.TelemetryEnabled,
			message = "Telemetry stopped"
		});

		return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 200));
	}

	private Task<MethodResponse> OnDefaultMethodAsync(MethodRequest request, object userContext)
	{
		var response = JsonSerializer.Serialize(new
		{
			ok = false,
			method = request.Name,
			error = "Unsupported direct method",
			allowedMethods = new[] { "setText", "getText", "setNumber", "getNumber", "startTelemetry", "stopTelemetry" }
		});

		Log($"Unsupported direct method '{request.Name}' received");
		return Task.FromResult(new MethodResponse(Encoding.UTF8.GetBytes(response), 404));
	}

	private async Task ReportStateAsync(string stateName)
	{
		var reported = new TwinCollection();
		var sim = new TwinCollection();
		sim["intervalSeconds"] = state.Config.IntervalSeconds;
		sim["randomEvery"] = state.Config.RandomEvery;
		sim["tempMin"] = state.Config.TempMin;
		sim["tempMax"] = state.Config.TempMax;
		sim["baseTemp"] = state.Config.BaseTemp;
		sim["sendCount"] = state.SendCount;
		sim["storedText"] = state.StoredText;
		sim["storedNumber"] = state.StoredNumber;
		sim["telemetryEnabled"] = state.TelemetryEnabled;
		sim["lastState"] = stateName;
		sim["lastUpdateUtc"] = DateTimeOffset.UtcNow.ToString("O");

		var app = new TwinCollection();
		app["name"] = "csharp-simulator";
		app["version"] = AppInfo.Version;

		var du = new TwinCollection();
		du["targetVersion"] = state.TargetVersion;
		du["restartRequested"] = state.RestartRequested;
		du["note"] = "Device Update package installation is external to this app.";

		reported["sim"] = sim;
		reported["app"] = app;
		reported["du"] = du;

		await client!.UpdateReportedPropertiesAsync(reported);
	}

	private void Log(string message)
	{
		if (quiet)
		{
			return;
		}

		Console.WriteLine($"[{deviceId}] {message}");
	}
}

internal sealed class DeviceState
{
	public SimConfig Config { get; } = new();
	public int SendCount { get; set; }
	public string StoredText { get; set; } = string.Empty;
	public int StoredNumber { get; set; }
	public bool TelemetryEnabled { get; set; } = true;
	public string TargetVersion { get; set; } = AppInfo.Version;
	public bool RestartRequested { get; set; }
}

internal sealed class SimConfig
{
	public double IntervalSeconds { get; set; } = 5;
	public int RandomEvery { get; set; } = 10;
	public double TempMin { get; set; } = 18;
	public double TempMax { get; set; } = 32;
	public double BaseTemp { get; set; } = 24;
}

internal sealed class DeviceEntry
{
	public string? DeviceId { get; set; }
	public string? ConnectionString { get; set; }
}

internal static class AppInfo
{
	public const string Version = "1.0.0";
}
