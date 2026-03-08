#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Stopping container..."
docker stop $(docker ps -q --filter ancestor=arduino-remote-flasher) 2>/dev/null || true

echo "Removing container..."
docker rm -f arduino-webapp 2>/dev/null || true

echo "Building image..."
docker build -t arduino-remote-flasher ./webapp

echo "Starting container..."
docker run -d --name arduino-webapp -p 5000:5000 --device /dev/ttyUSB0 \
  -e TZ=Asia/Kolkata \
  -v "$(pwd)":/workspace -v arduino15:/app/.arduino15 \
  -e HOME=/app \
  arduino-remote-flasher

echo "Done. Web app at http://$(hostname -I | awk '{print $1}'):5000"
