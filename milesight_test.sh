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

#!/usr/bin/env bash
set -u

###############################################################################
# MILESIGHT MQTT TEST TOOL
#
# Models:
#   1) WS502      - two-channel wall switch
#   2) WS558      - eight-channel relay controller
#   3) VALVE      - timed irrigation valve protocol
#
# Requirements:
#   mosquitto-clients, xxd, base64
#
# All commands are converted from HEX to Base64 before MQTT publication.
###############################################################################

###############################################################################
# MQTT CONFIGURATION
###############################################################################

MQTT_HOST=".........."
MQTT_PORT="1883"
MQTT_USER=".........."
MQTT_PASS=".........."

TOPIC="ug/downlinkdata"
FPORT=85
CONFIRMED=true

###############################################################################
# DEVICE CONFIGURATION
###############################################################################

WS502_EUI=".........."
WS558_EUI=".........."
VALVE_EUI=".........."

###############################################################################
# TIMING CONFIGURATION
###############################################################################

STEP_DELAY=3
ON_SECONDS=5
VALVE_SECONDS=300

###############################################################################
# DEBUG
###############################################################################

DEBUG=true

log_debug() {
    if [[ "$DEBUG" == true ]]; then
        printf '[DEBUG] %s\n' "$*" >&2
    fi
}

###############################################################################
# COMMON HELPERS
###############################################################################

print_separator() {
    printf '%*s\n' 78 '' | tr ' ' '='
}

hex2b64() {
    printf '%s' "$1" | xxd -r -p | base64 -w0
}

send_hex() {
    local DEVICE="$1"
    local HEX="$2"
    local NAME="$3"
    local B64 JSON

    # Reject malformed hexadecimal strings.
    if [[ ! "$HEX" =~ ^([[:xdigit:]]{2})+$ ]]; then
        echo "ERROR: invalid HEX payload: $HEX" >&2
        return 1
    fi

    B64=$(hex2b64 "$HEX") || return 1

    JSON=$(printf \
        '{"devEui":"%s","confirmed":%s,"fPort":%s,"data":"%s"}' \
        "$DEVICE" "$CONFIRMED" "$FPORT" "$B64")

    print_separator
    echo "Timestamp : $(date '+%F %T')"
    echo "Device    : $DEVICE"
    echo "Command   : $NAME"
    echo "HEX       : $HEX"
    echo "Base64    : $B64"
    echo "Topic     : $TOPIC"
    echo
    echo "MQTT payload:"
    echo "$JSON"
    print_separator

    log_debug "Publishing to $MQTT_HOST:$MQTT_PORT"

    if mosquitto_pub \
        -h "$MQTT_HOST" \
        -p "$MQTT_PORT" \
        -u "$MQTT_USER" \
        -P "$MQTT_PASS" \
        -t "$TOPIC" \
        -m "$JSON"
    then
        echo "Result    : MQTT publish OK"
    else
        echo "Result    : MQTT publish FAILED"
        return 1
    fi

    echo
}

###############################################################################
# WS502 - TWO CHANNELS
#
# Commands confirmed in the existing installation:
#   L1 ON  : 0811ff
#   L1 OFF : 0810ff
#   L2 ON  : 0822ff
#   L2 OFF : 0820ff
###############################################################################

ws502_menu() {
    local DEVICE="$WS502_EUI"
    local CHOICE

    while true; do
        print_separator
        echo "WS502 - TWO CHANNEL SWITCH"
        echo "Device: $DEVICE"
        print_separator
        echo "1) L1 ON"
        echo "2) L1 OFF"
        echo "3) L2 ON"
        echo "4) L2 OFF"
        echo "5) L1 ON, then L2 ON"
        echo "6) L1 OFF, then L2 OFF"
        echo "0) Back to model selection"
        read -r -p "Action: " CHOICE

        case "$CHOICE" in
            1) send_hex "$DEVICE" "0811ff" "WS502 L1 ON" ;;
            2) send_hex "$DEVICE" "0810ff" "WS502 L1 OFF" ;;
            3) send_hex "$DEVICE" "0822ff" "WS502 L2 ON" ;;
            4) send_hex "$DEVICE" "0820ff" "WS502 L2 OFF" ;;
            5)
                send_hex "$DEVICE" "0811ff" "WS502 L1 ON" || continue
                sleep "$STEP_DELAY"
                send_hex "$DEVICE" "0822ff" "WS502 L2 ON"
                ;;
            6)
                send_hex "$DEVICE" "0810ff" "WS502 L1 OFF" || continue
                sleep "$STEP_DELAY"
                send_hex "$DEVICE" "0820ff" "WS502 L2 OFF"
                ;;
            0) return ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

###############################################################################
# WS558 - EIGHT CHANNELS
#
# All channels:
#   ALL OFF : 08ff00
#   ALL ON  : 08ffff
#
# Individual-channel masks below follow the bit-mask protocol assumption.
# Validate individual channel commands against the WS558 documentation/device.
###############################################################################

ws558_menu() {
    local DEVICE="$WS558_EUI"
    local CHOICE

    while true; do
        print_separator
        echo "WS558 - EIGHT CHANNEL RELAY"
        echo "Device: $DEVICE"
        print_separator
        echo "1) All relays ON"
        echo "2) All relays OFF"
        echo "3) Sequential activation L1 -> L8"
        echo "4) Each relay ON for 5 seconds, then OFF"
        echo "5) Select individual relay"
        echo "0) Back to model selection"
        read -r -p "Action: " CHOICE

        case "$CHOICE" in
            1) send_hex "$DEVICE" "08ffff" "WS558 ALL ON" ;;
            2) send_hex "$DEVICE" "08ff00" "WS558 ALL OFF" ;;
            3) ws558_sequence "$DEVICE" ;;
            4) ws558_timed "$DEVICE" ;;
            5) ws558_individual "$DEVICE" ;;
            0) return ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

ws558_individual() {
    local DEVICE="$1"
    local N BIT MASK HEX CHOICE

    read -r -p "Relay number (1-8): " N

    if [[ ! "$N" =~ ^[1-8]$ ]]; then
        echo "Invalid relay number"
        return 1
    fi

    BIT=$((1 << (N - 1)))
    printf -v MASK '%02x' "$BIT"

    echo "1) ON"
    echo "2) OFF"
    read -r -p "State: " CHOICE

    case "$CHOICE" in
        1) HEX="08${MASK}${MASK}" ;;
        2) HEX="08${MASK}00" ;;
        *) echo "Invalid state"; return 1 ;;
    esac

    send_hex "$DEVICE" "$HEX" "WS558 L${N}"
}

ws558_sequence() {
    local DEVICE="$1"
    local N BIT MASK HEX

    echo "Sequential activation: L1 -> L8"

    for N in {1..8}; do
        BIT=$((1 << (N - 1)))
        printf -v MASK '%02x' "$BIT"
        HEX="08${MASK}${MASK}"

        send_hex "$DEVICE" "$HEX" "WS558 L${N} ON" || return 1
        sleep "$STEP_DELAY"
    done
}

ws558_timed() {
    local DEVICE="$1"
    local N BIT MASK HEX_ON HEX_OFF

    echo "Each relay ON for ${ON_SECONDS} seconds, then OFF."

    for N in {1..8}; do
        BIT=$((1 << (N - 1)))
        printf -v MASK '%02x' "$BIT"

        HEX_ON="08${MASK}${MASK}"
        HEX_OFF="08${MASK}00"

        send_hex "$DEVICE" "$HEX_ON" "WS558 L${N} ON" || return 1
        sleep "$ON_SECONDS"
        send_hex "$DEVICE" "$HEX_OFF" "WS558 L${N} OFF" || return 1
        sleep "$STEP_DELAY"
    done
}

###############################################################################
# VALVE - ORIGINAL PROTOCOL
#
# These commands belong to the original valve protocol, not WS502/WS558.
###############################################################################

VALVE_OPEN="ff1d2000"
VALVE_CLOSE="ff1d0001"
VALVE_OPEN_2MIN="ff1da002780000"
VALVE_OPEN_5MIN="ff1da0022c0100"

valve_menu() {
    local DEVICE="$VALVE_EUI"
    local CHOICE

    while true; do
        print_separator
        echo "VALVE - IRRIGATION CONTROL"
        echo "Device: $DEVICE"
        print_separator
        echo "1) OPEN"
        echo "2) CLOSE"
        echo "3) OPEN valve for 2 minutes"
        echo "4) OPEN valve for 5 minutes"
        echo "0) Back to model selection"
        read -r -p "Action: " CHOICE

        case "$CHOICE" in
            1) send_hex "$DEVICE" "$VALVE_OPEN" "VALVE OPEN" ;;
            2) send_hex "$DEVICE" "$VALVE_CLOSE" "VALVE CLOSE" ;;
            3) send_hex "$DEVICE" "$VALVE_OPEN_2MIN" "VALVE OPEN 2 MIN" ;;
            4) send_hex "$DEVICE" "$VALVE_OPEN_5MIN" "VALVE OPEN 5 MIN" ;;
            0) return ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

###############################################################################
# MAIN - SELECT MODEL, THEN SHOW MODEL-SPECIFIC MENU
###############################################################################

while true; do
    print_separator
    echo "MILE­SIGHT MQTT TEST TOOL"
    print_separator
    echo "1) WS502 - 2-channel switch"
    echo "2) WS558 - 8-channel relay"
    echo "3) Valve - irrigation protocol"
    echo "0) Exit"
    read -r -p "Select model: " MODEL

    case "$MODEL" in
        1) ws502_menu ;;
        2) ws558_menu ;;
        3) valve_menu ;;
        0) echo "Exit"; exit 0 ;;
        *) echo "Invalid model" ;;
    esac
done
