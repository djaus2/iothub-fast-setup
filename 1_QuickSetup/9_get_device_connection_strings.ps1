$IOTHUB_NAME = $env:IOTHUB_NAME

if ([string]::IsNullOrWhiteSpace($IOTHUB_NAME)) {
  throw "Set non-empty IOTHUB_NAME environment variable first."
}

for ($i=1; $i -le 10; $i++) {
  $d = "device$i"
  $cs = az iot hub device-identity connection-string show -n $IOTHUB_NAME -d $d --query connectionString -o tsv
  Write-Output "$d`t$cs"
}
