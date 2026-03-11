FROM python:3-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    screen \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/bin \
    && curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR=/usr/local/bin sh

RUN pip install --no-cache-dir pyserial

# Ensure cores are installed under /app/.arduino15 so they are picked up when HOME=/app
ENV HOME=/app
RUN mkdir -p "$HOME" \
    && arduino-cli config init || true \
    && arduino-cli core update-index \
    && arduino-cli core install arduino:avr \
    && arduino-cli lib install "Time" "DS1307RTC" "MD_Parola" "MD_MAX72XX" "DS3231"

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY templates/ templates/

EXPOSE 5000
CMD ["python", "app.py"]
