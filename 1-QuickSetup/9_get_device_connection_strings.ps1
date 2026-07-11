for ($i=1; $i -le 10; $i++) {
  $d = "device$i"
  $cs = az iot hub device-identity connection-string show -n my-iot-hub-137 -d $d --query connectionString -o tsv
  Write-Output "$d`t$cs"
}
