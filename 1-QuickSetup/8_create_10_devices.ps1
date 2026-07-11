for ($i=1; $i -le 10; $i++) {
  az iot hub device-identity create -n my-iot-hub-137 -d ("device" + $i)
}
