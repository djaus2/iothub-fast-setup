for ($i=1; $i -le 10; $i++) {
  $d = "device$i"
  az iot hub device-identity show -n my-iot-hub-137 -d $d --query deviceId -o tsv 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) {
    az iot hub device-identity create -n my-iot-hub-137 -d $d | Out-Null
  }
}
