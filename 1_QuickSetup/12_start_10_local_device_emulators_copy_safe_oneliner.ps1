$IOTHUB_NAME = $env:IOTHUB_NAME

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME)) {
	throw "Set non-empty IOTHUB_NAME environment variable first."
}

$hub=$IOTHUB_NAME; 1..10 | ForEach-Object { $d = "device$_"; Start-Job -Name "iot-$d" -ScriptBlock { param($h,$device) az iot device simulate -n $h -d $device --msg-count 1000000 --msg-interval 5 --data "Ping from $device" --only-show-errors } -ArgumentList $hub,$d | Out-Null }; Get-Job -Name 'iot-device*' | Select-Object Name,State,PSBeginTime
