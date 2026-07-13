$IOTHUB_NAME = $env:IOTHUB_NAME
$IOT_RG = $env:IOT_RG

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME) -or [string]::IsNullOrWhiteSpace($IOT_RG)) {
	throw "Set non-empty IOTHUB_NAME and/or IOT_RG environment variables first."
}

az group create -n $IOT_RG -l australiaeast
az iot hub create -g $IOT_RG -n $IOTHUB_NAME --sku S1 --partition-count 2
