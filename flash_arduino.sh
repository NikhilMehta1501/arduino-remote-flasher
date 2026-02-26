#!/bin/bash

# Script to compile and flash Arduino programs to a clone Arduino Nano
# First flashes SetTimeUseMe, verifies time +5 mins, then flashes Matrix_Clock

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
# Try old bootloader first (common for clones), fallback to new bootloader
BOARD_FQBN_OLD="arduino:avr:nano:cpu=atmega328old"
BOARD_FQBN_NEW="arduino:avr:nano:cpu=atmega328"
BOARD_FQBN=""  # Will be determined based on what works
SERIAL_BAUD=9600
MONITOR_TIMEOUT=30  # seconds to wait for serial output

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTIME_DIR="${SCRIPT_DIR}/firmware/SetTimeUseMe"
MATRIX_DIR="${SCRIPT_DIR}/firmware/Matrix_Clock"

echo -e "${GREEN}=== Arduino Flash Script ===${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to find Arduino port
find_arduino_port() {
    local port=""
    
    # Get list of all ports from arduino-cli
    local all_ports=$(arduino-cli board list | grep -E "tty(USB|ACM|AMA)" | awk '{print $1}')
    
    # Prioritize USB devices (ttyUSB* and ttyACM*) over UART (ttyAMA*)
    # USB devices are more likely to be the actual Arduino
    for dev in $all_ports; do
        if echo "$dev" | grep -qE "tty(USB|ACM)"; then
            port="$dev"
            break
        fi
    done
    
    # If no USB device found, try UART as fallback
    if [ -z "$port" ]; then
        for dev in $all_ports; do
            if echo "$dev" | grep -q "ttyAMA"; then
                port="$dev"
                break
            fi
        done
    fi
    
    # Final fallback: use first port from list
    if [ -z "$port" ]; then
        port=$(echo "$all_ports" | head -1)
    fi
    
    if [ -z "$port" ]; then
        echo -e "${RED}Error: No Arduino board detected!${NC}"
        echo "Please connect your Arduino Nano and try again."
        echo "Available ports:"
        arduino-cli board list
        exit 1
    fi
    
    echo "$port"
}

# Check for arduino-cli
if ! command_exists arduino-cli; then
    echo -e "${YELLOW}arduino-cli not found. Installing...${NC}"
    
    # Install arduino-cli
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
    
    # Add to PATH if not already there
    if [ -d "$HOME/local/bin" ] && [[ ":$PATH:" != *":$HOME/local/bin:"* ]]; then
        export PATH="$HOME/local/bin:$PATH"
    fi
fi

# Check for screen (for serial monitoring)
if ! command_exists screen; then
    echo -e "${YELLOW}screen not found. Installing...${NC}"
    sudo apt-get update && sudo apt-get install -y screen
fi

# Initialize arduino-cli if needed
if [ ! -f "$HOME/.arduino15/arduino-cli.yaml" ]; then
    echo -e "${YELLOW}Initializing arduino-cli...${NC}"
    arduino-cli config init
fi

# Update core index
echo -e "${GREEN}Updating core index...${NC}"
arduino-cli core update-index

# Install Arduino AVR core
echo -e "${GREEN}Installing Arduino AVR core...${NC}"
arduino-cli core install arduino:avr

# Install required libraries
echo -e "${GREEN}Installing required libraries...${NC}"

# Libraries for SetTimeUseMe
arduino-cli lib install "Time" || echo -e "${YELLOW}Time library may already be installed${NC}"
arduino-cli lib install "DS1307RTC" || echo -e "${YELLOW}DS1307RTC library may already be installed${NC}"

# Libraries for Matrix_Clock
arduino-cli lib install "MD_Parola" || echo -e "${YELLOW}MD_Parola library may already be installed${NC}"
arduino-cli lib install "MD_MAX72XX" || echo -e "${YELLOW}MD_MAX72XX library may already be installed${NC}"
arduino-cli lib install "DS3231" || echo -e "${YELLOW}DS3231 library may already be installed${NC}"

# Find Arduino port
echo -e "${GREEN}Detecting Arduino board...${NC}"
ARDUINO_PORT=$(find_arduino_port)
echo -e "${GREEN}Found Arduino at: ${ARDUINO_PORT}${NC}"

# Check if user has permission to access the serial port
if [ ! -r "$ARDUINO_PORT" ] || [ ! -w "$ARDUINO_PORT" ]; then
    echo -e "${YELLOW}Warning: May not have permission to access ${ARDUINO_PORT}${NC}"
    if ! groups | grep -q dialout; then
        echo -e "${RED}You are not in the dialout group!${NC}"
        echo -e "${YELLOW}Adding you to dialout group...${NC}"
        sudo usermod -a -G dialout $USER
        echo -e "${GREEN}Added to dialout group.${NC}"
        echo -e "${YELLOW}You may need to log out and back in, or run: newgrp dialout${NC}"
        echo -e "${YELLOW}Alternatively, you can continue and the script will try with sudo if needed.${NC}"
    else
        echo -e "${YELLOW}You are in dialout group, but still may have permission issues.${NC}"
        echo -e "${YELLOW}If upload fails, try running with sudo or check port permissions.${NC}"
    fi
fi

# Verify port exists and is accessible
if [ ! -e "$ARDUINO_PORT" ]; then
    echo -e "${RED}Error: Port ${ARDUINO_PORT} does not exist!${NC}"
    echo "Available ports:"
    arduino-cli board list
    exit 1
fi

# Default to old bootloader for clone Nanos (most common)
BOARD_FQBN="$BOARD_FQBN_OLD"
echo -e "${GREEN}Using board: ${BOARD_FQBN}${NC}"
echo -e "${YELLOW}Note: If upload fails, the script will try the new bootloader automatically${NC}"

# Function to reset Arduino via DTR (Data Terminal Ready)
reset_arduino_dtr() {
    local port="$1"
    
    # Check if pyserial is available
    if python3 -c "import serial" 2>/dev/null; then
        # Use Python to toggle DTR (most reliable method)
        # Minimal delay - just enough to trigger bootloader
        python3 << EOF
import serial
import time
try:
    ser = serial.Serial("$port", 1200)
    time.sleep(0.05)  # Minimal delay
    ser.close()
    time.sleep(0.1)    # Short delay before upload
except:
    pass
EOF
    elif command_exists stty; then
        # Alternative: use stty to set baud to 1200 (triggers bootloader on some boards)
        stty -F "$port" 1200 >/dev/null 2>&1 || true
        sleep 0.1
        stty -F "$port" 9600 >/dev/null 2>&1 || true
        sleep 0.2
    fi
}

# Function to prepare serial port for upload (for CH341 and similar chips)
prepare_serial_port() {
    local port="$1"
    
    # Try to reset Arduino into bootloader mode
    echo -e "${YELLOW}Resetting Arduino to bootloader mode...${NC}"
    reset_arduino_dtr "$port"
}

# Function to compile and upload
compile_and_upload() {
    local sketch_dir="$1"
    local sketch_name="$2"
    local fqbn="$3"
    
    echo -e "${GREEN}=== Compiling ${sketch_name} ===${NC}"
    if ! arduino-cli compile --fqbn "$fqbn" "$sketch_dir"; then
        echo -e "${RED}Compilation failed for ${sketch_name}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}=== Uploading ${sketch_name} to ${ARDUINO_PORT} ===${NC}"
    
    # For CH341-based clones, reset and upload immediately
    if echo "$ARDUINO_PORT" | grep -q "ttyUSB"; then
        echo -e "${YELLOW}Resetting Arduino to bootloader mode...${NC}"
        # Fast reset using Python
        python3 << EOF 2>/dev/null
import serial, time
try:
    s = serial.Serial("$ARDUINO_PORT", 1200)
    time.sleep(0.05)
    s.close()
except: pass
EOF
        echo -e "${YELLOW}Starting upload immediately...${NC}"
        # No delay - upload right away while bootloader is active
    else
        echo -e "${YELLOW}Preparing Arduino for upload...${NC}"
        prepare_serial_port "$ARDUINO_PORT"
        sleep 1
    fi
    
    # Try upload (arduino-cli handles DTR reset automatically)
    echo -e "${YELLOW}Attempting upload...${NC}"
    if arduino-cli upload -p "$ARDUINO_PORT" --fqbn "$fqbn" "$sketch_dir" --verbose 2>&1; then
        echo -e "${GREEN}Successfully uploaded ${sketch_name}!${NC}"
        sleep 2  # Wait for board to reset
        return 0
    else
        local upload_error=$?
        
        # If old bootloader fails, try new bootloader
        if [ "$fqbn" = "$BOARD_FQBN_OLD" ]; then
            echo -e "${YELLOW}Upload with old bootloader failed, trying new bootloader...${NC}"
            if echo "$ARDUINO_PORT" | grep -q "ttyUSB"; then
                # Fast reset for CH341
                python3 << EOF 2>/dev/null
import serial, time
try:
    s = serial.Serial("$ARDUINO_PORT", 1200)
    time.sleep(0.05)
    s.close()
except: pass
EOF
            else
                prepare_serial_port "$ARDUINO_PORT"
                sleep 1
            fi
            if arduino-cli compile --fqbn "$BOARD_FQBN_NEW" "$sketch_dir" && \
               arduino-cli upload -p "$ARDUINO_PORT" --fqbn "$BOARD_FQBN_NEW" "$sketch_dir" --verbose 2>&1; then
                echo -e "${GREEN}Successfully uploaded ${sketch_name} with new bootloader!${NC}"
                BOARD_FQBN="$BOARD_FQBN_NEW"  # Update for next upload
                sleep 2
                return 0
            fi
        fi
        
        
        # Check if it's a permission error
        if [ $upload_error -ne 0 ]; then
            echo -e "${RED}Upload failed for ${sketch_name}${NC}"
            echo ""
            echo -e "${YELLOW}=== Troubleshooting Steps ===${NC}"
            echo ""
            echo "For CH341-based clone Arduinos, the timing is critical. Try this:"
            echo ""
            echo "Method 1 - Use reset helper script (RECOMMENDED):"
            echo "  1. In terminal 1, run: ./reset_arduino.sh $ARDUINO_PORT"
            echo "  2. IMMEDIATELY (within 1 second) in terminal 2, run:"
            echo "     arduino-cli upload -p $ARDUINO_PORT --fqbn $fqbn $sketch_dir"
            echo ""
            echo "Method 2 - Manual reset:"
            echo "  1. Press and HOLD the RESET button on the Arduino"
            echo "  2. While holding RESET, run: stty -F $ARDUINO_PORT 1200"
            echo "  3. Release RESET button"
            echo "  4. IMMEDIATELY (within 1 second) run the upload command"
            echo ""
            echo "Method 3 - Try different bootloader:"
            echo "  If using old bootloader, try: --fqbn arduino:avr:nano:cpu=atmega328"
            echo "  If using new bootloader, try: --fqbn arduino:avr:nano:cpu=atmega328old"
            echo ""
            echo "Check permissions:"
            echo "  ls -l $ARDUINO_PORT"
            echo "  groups | grep dialout"
        fi
        return 1
    fi
}

# Function to monitor serial and verify time
monitor_serial_verify_time() {
    local port="$1"
    local timeout="$2"
    local expected_minute_offset=5
    local current_minute=$(date +%M | sed 's/^0//')  # Remove leading zero
    local expected_minute=$(( (current_minute + expected_minute_offset) % 60 ))
    local current_hour=$(date +%H | sed 's/^0//')
    
    echo -e "${GREEN}=== Monitoring serial output (expecting time +5 minutes) ===${NC}"
    echo "Current system time: $(date +%H:%M:%S)"
    echo "Expected RTC minute should be: $expected_minute (current minute $current_minute + 5)"
    echo "Monitoring for up to ${timeout} seconds..."
    echo "Press Ctrl+C to stop monitoring early"
    echo ""
    
    # Create a temporary file for output
    local temp_file=$(mktemp)
    local monitor_pid
    
    # Start monitoring in background
    (
        arduino-cli monitor -p "$port" -c baudrate="$SERIAL_BAUD" 2>&1 | tee "$temp_file"
    ) &
    monitor_pid=$!
    
    # Wait for timeout or successful verification
    local elapsed=0
    local verified=0
    
    while [ $elapsed -lt $timeout ] && [ $verified -eq 0 ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        
        # Check if we have time output
        if grep -q "Time = " "$temp_file" 2>/dev/null; then
            # Get the last time line
            local time_line=$(grep "Time = " "$temp_file" | tail -1)
            echo "$time_line"
            
            # Extract minute (format: "Time = HH:MM:SS")
            local minute=$(echo "$time_line" | sed -n 's/.*Time = [0-9]*:\([0-9]*\):.*/\1/p' | sed 's/^0//')
            
            if [ -n "$minute" ] && [ "$minute" != "" ]; then
                echo -e "${GREEN}Detected RTC minute: $minute${NC}"
                # Allow some tolerance (±2 minutes for clock drift)
                local diff=$(( (minute - expected_minute + 60) % 60 ))
                if [ $diff -le 2 ] || [ $diff -ge 58 ]; then
                    echo -e "${GREEN}✓ Time verification successful! RTC shows time +5 minutes (minute: $minute).${NC}"
                    verified=1
                    kill $monitor_pid 2>/dev/null || true
                    break
                fi
            fi
        fi
        
        # Print progress every 5 seconds
        if [ $((elapsed % 5)) -eq 0 ]; then
            echo -e "${YELLOW}[${elapsed}s/${timeout}s] Waiting for serial output...${NC}"
        fi
    done
    
    # Clean up
    kill $monitor_pid 2>/dev/null || true
    sleep 1
    kill -9 $monitor_pid 2>/dev/null || true
    
    # Show recent output
    echo ""
    echo -e "${GREEN}Recent serial output:${NC}"
    tail -20 "$temp_file" 2>/dev/null || true
    rm -f "$temp_file"
    
    if [ $verified -eq 1 ]; then
        return 0
    else
        echo -e "${YELLOW}Note: Time verification timeout. Please manually verify the serial output above.${NC}"
        echo -e "${YELLOW}You can manually monitor with: arduino-cli monitor -p $port -c baudrate=$SERIAL_BAUD${NC}"
        return 0  # Don't fail, just warn
    fi
}

# Step 1: Flash SetTimeUseMe
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step 1: Flashing SetTimeUseMe${NC}"
echo -e "${GREEN}========================================${NC}"
if ! compile_and_upload "$SETTIME_DIR" "SetTimeUseMe" "$BOARD_FQBN"; then
    echo -e "${RED}Failed to flash SetTimeUseMe${NC}"
    exit 1
fi

# Step 2: Monitor serial and verify time
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step 2: Verifying time setting${NC}"
echo -e "${GREEN}========================================${NC}"
monitor_serial_verify_time "$ARDUINO_PORT" "$MONITOR_TIMEOUT"

# Wait a bit before flashing next program
echo -e "${GREEN}Waiting 3 seconds before flashing Matrix Clock...${NC}"
sleep 3

# Step 3: Flash Matrix_Clock
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step 3: Flashing Matrix_Clock${NC}"
echo -e "${GREEN}========================================${NC}"
if ! compile_and_upload "$MATRIX_DIR" "Matrix_Clock" "$BOARD_FQBN"; then
    echo -e "${RED}Failed to flash Matrix_Clock${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ All done! Both programs have been flashed.${NC}"
echo -e "${GREEN}========================================${NC}"
