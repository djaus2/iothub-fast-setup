$IOTHUB_NAME = $env:IOTHUB_NAME

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME)) {
	throw "Set non-empty IOTHUB_NAME environment variable first."
}

az iot hub device-identity list -n $IOTHUB_NAME --query "[].deviceId" -o table
