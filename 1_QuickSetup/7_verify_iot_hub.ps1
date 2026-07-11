az iot hub show -n my-iot-hub-137 --query "{name:name,sku:sku.name,state:properties.state,hostname:properties.hostName}" -o json
