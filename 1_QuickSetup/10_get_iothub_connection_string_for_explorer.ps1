$IOTHUB_NAME = $env:IOTHUB_NAME

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME)) {
	throw "Set non-empty IOTHUB_NAME environment variable first."
}

az iot hub connection-string show -n $IOTHUB_NAME --policy-name iothubowner --key primary --query connectionString -o tsv
