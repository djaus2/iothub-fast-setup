az group create -n My-IoT-Grp-137 -l australiaeast
az iot hub create -g My-IoT-Grp-137 -n my-iot-hub-137 --sku B1 --partition-count 2
