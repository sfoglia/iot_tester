#!/usr/bin/env bash
###############################################################################
# Milesight Valve MQTT test
###############################################################################
"""
Copyright (C) 2026 - Chiara Fornoni

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
"""
set -u


MQTT_HOST=".........."
MQTT_PORT="1883"
MQTT_USER=".........."
MQTT_PASS=".........."

APPLICATION_ID="1"

###############################################################################
# Device configuration
###############################################################################

DEVICE_EUI=".........."

TOPIC="........../downlinkdata"
FPORT=85
CONFIRMED=true

###############################################################################
# Commands
###############################################################################

OPEN="ff1d2000"
OPEN_NAME="OPEN"

CLOSE="ff1d0001"
CLOSE_NAME="CLOSE"

OPEN_V1_2_MIN="ff1da002780000"
OPEN_V1_2_MIN_NAME="OPEN valve 1 for 2 minutes"

OPEN_V1_5_MIN="ff1da0022c0100"
OPEN_V1_5_MIN_NAME="OPEN valve 1 for 5 minutes"

###############################################################################
# Helpers
###############################################################################

hex2b64() {
    printf "%s" "$1" | xxd -r -p | base64 -w0
}

print_separator() {
    printf '%*s\n' 78 '' | tr ' ' '='
}

send_hex() {

    local HEX="$1"
    local NAME="$2"

    local B64
    B64=$(hex2b64 "$HEX")

    local JSON
    JSON=$(cat <<EOF
{
  "devEui":"${DEVICE_EUI}",
  "confirmed":${CONFIRMED},
  "fPort":${FPORT},
  "data":"${B64}"
}
EOF
)

    print_separator
    echo "Timestamp : $(date '+%F %T')"
    echo "Device    : ${DEVICE_EUI}"
    echo "Command   : ${NAME}"
    echo "HEX       : ${HEX}"
    echo "Base64    : ${B64}"
    echo "Topic     : ${TOPIC}"
    echo

    echo "MQTT Payload"
    echo "${JSON}"

    print_separator

    if mosquitto_pub \
        -h "${MQTT_HOST}" \
        -p "${MQTT_PORT}" \
        -u "${MQTT_USER}" \
        -P "${MQTT_PASS}" \
        -t "${TOPIC}" \
        -m "${JSON}"
    then
        echo "Result    : MQTT message published successfully."
    else
        echo "Result    : ERROR publishing MQTT message."
    fi

    echo
}

###############################################################################
# Test 1
###############################################################################

echo
print_separator
echo "TEST 1"
echo
echo "Description:"
echo "  Send only a timed irrigation command."
echo
echo "Expected:"
echo "  Valve opens immediately and closes automatically after 5 minutes."
print_separator

send_hex "$OPEN_V1_5_MIN" "$OPEN_V1_5_MIN_NAME"

###############################################################################
# Test 2
###############################################################################
echo "wait for timed execution to complete"
sleep 305
echo

print_separator
echo "TEST 2"
echo
echo "Description:"
echo "  OPEN"
echo "  wait 60 seconds"
echo "  CLOSE"
echo "  wait 5 seconds"
echo "  OPEN for 5 minutes"
echo
echo "Expected:"
echo "  Timed irrigation command is executed."
print_separator

send_hex "$OPEN" "$OPEN_NAME"

sleep 60

send_hex "$CLOSE" "$CLOSE_NAME"

sleep 5

send_hex "$OPEN_V1_5_MIN" "$OPEN_V1_5_MIN_NAME"

###############################################################################
# Reference payloads
###############################################################################

: <<'REFERENCE'

OPEN
  HEX    : ff1d2000
  Base64 : /x0gAA==

CLOSE
  HEX    : ff1d0001
  Base64 : /x0AAQ==

OPEN valve 1 for 2 minutes
  HEX    : ff1da002780000
  Base64 : /x2gAngAAA==

OPEN valve 1 for 5 minutes
  HEX    : ff1da0022c0100
  Base64 : /x2gAiwBAA==

REFERENCE
