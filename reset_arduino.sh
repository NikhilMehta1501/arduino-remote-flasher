#!/bin/bash
# Helper script to reset Arduino into bootloader mode
# Usage: ./reset_arduino.sh [port]

PORT="${1:-/dev/ttyUSB0}"

if [ ! -e "$PORT" ]; then
    echo "Error: Port $PORT does not exist"
    echo "Available ports:"
    arduino-cli board list 2>/dev/null | grep -E "tty(USB|ACM)" || echo "  (none found)"
    exit 1
fi

echo "Resetting Arduino on $PORT to bootloader mode..."

if python3 -c "import serial" 2>/dev/null; then
    python3 << EOF
import serial
import time
try:
    print("Opening port at 1200 baud (triggers bootloader)...")
    ser = serial.Serial("$PORT", 1200)
    time.sleep(0.1)
    ser.close()
    time.sleep(0.5)
    print("Reset complete! Arduino should be in bootloader mode for ~8 seconds.")
    print("You can now upload a sketch.")
except Exception as e:
    print(f"Error: {e}")
    print("Make sure you have permission to access $PORT")
    print("Try: sudo usermod -a -G dialout \$USER && newgrp dialout")
EOF
elif command -v stty >/dev/null 2>&1; then
    stty -F "$PORT" 1200 2>/dev/null || { echo "Error: Could not set baud rate. Check permissions."; exit 1; }
    sleep 0.2
    stty -F "$PORT" 9600 2>/dev/null
    sleep 0.3
    echo "Reset complete!"
else
    echo "Error: Need either python3 with pyserial or stty command"
    exit 1
fi
