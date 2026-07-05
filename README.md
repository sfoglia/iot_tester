# iot_tester
bash script to test expected behavior

## REQUIREMENTS:
- bash
- mqtt
- milesight device EUI

## RUN
Terminal 1:
```bash ./milesight_test.sh```
Terminal 2:
```mosquitto_sub -t "#"```
