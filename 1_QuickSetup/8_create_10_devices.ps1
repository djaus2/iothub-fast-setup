$IOTHUB_NAME = $env:IOTHUB_NAME

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME)) {
  throw "Set non-empty IOTHUB_NAME environment variable first."
}

for ($i=1; $i -le 10; $i++) {
  az iot hub device-identity create -n $IOTHUB_NAME -d ("device" + $i)
}
