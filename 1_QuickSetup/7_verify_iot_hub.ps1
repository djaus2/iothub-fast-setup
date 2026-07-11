$IOTHUB_NAME = $env:IOTHUB_NAME

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME)) {
	throw "Set non-empty IOTHUB_NAME environment variable first."
}

az iot hub show -n $IOTHUB_NAME --query "{name:name,sku:sku.name,state:properties.state,hostname:properties.hostName}" -o json
