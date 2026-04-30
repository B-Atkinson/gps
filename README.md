# GPS Collector

GPS Collector reads NMEA messages from a USB-connected GPS puck and stores the raw sentences in a local SQLite database. The main entrypoint is [gps_reader.py](/home/brian/PycharmProjects/gps_collector/gps_reader.py), with container support defined in [Dockerfile](/home/brian/PycharmProjects/gps_collector/Dockerfile) and [compose.yaml](/home/brian/PycharmProjects/gps_collector/compose.yaml).

## Purpose

This project is for collecting GPS NMEA messages received by a GPS puck. It watches serial ports, connects to the GPS device, parses the incoming NMEA stream, and records the original sentences in SQLite for later review or downstream processing.

## What It Does

- Detects likely GPS serial devices automatically on Linux and Windows
- Connects to a GPS receiver at `9600` baud
- Parses NMEA sentences with `pynmea2`
- Stores every received sentence in SQLite
- Marks recognized, valid NMEA messages as `verified = true`

The `gps_data` table contains:

- `id`
- `verified`
- `gps_date`
- `gps_time`
- `raw_sentence`

## Repository Layout

- `gps_reader.py`: serial port detection, NMEA parsing, and SQLite writes
- `Dockerfile`: Ubuntu-based image that installs Python, `pyserial`, and `pynmea2`
- `compose.yaml`: long-running container setup with `/dev` access and a persistent database volume

## Clone The Repository

```bash
git clone https://github.com/B-Atkinson/gps.git
cd gps_collector
```

Replace `https://github.com/B-Atkinson/gps.git` with the URL for your Git remote.

## Install And Run Locally

### Requirements

- Python 3.10+ recommended
- A USB GPS puck that presents itself as a serial device
- Linux, Raspberry Pi OS, or Windows

### Create A Virtual Environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install pyserial==3.5 pynmea2==1.19.0
```

### Start The Reader

```bash
python3 gps_reader.py
```

By default the script:

- Scans available serial ports
- Chooses a GPS-like device if one is detected
- Creates or updates `gps_data.db` in the current directory
- Continues reading until you stop it with `Ctrl+C`

### Useful Command Examples

Write to a specific database file:

```bash
python3 gps_reader.py --database /path/to/gps_data.db
```

Use a specific serial device instead of auto-detection:

```bash
python3 gps_reader.py --port /dev/ttyUSB0 --database ./gps_data.db
```

On Windows, the port argument would look like:

```bash
python3 gps_reader.py --port COM3
```

## Run On A Raspberry Pi With A USB GPS Puck

These steps assume Raspberry Pi OS and a GPS puck connected over USB.

### 1. Connect The GPS Puck

Plug the puck into a USB port on the Raspberry Pi.

### 2. Confirm The Serial Device

List serial devices:

```bash
ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

If your GPS is detected, it will usually appear as something like `/dev/ttyUSB0` or `/dev/ttyACM0`.

You can also inspect kernel messages:

```bash
dmesg | tail
```

### 3. Clone The Project

```bash
git clone https://github.com/B-Atkinson/gps.git
cd gps_collector
```

### 4. Run It Directly On The Pi

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install pyserial==3.5 pynmea2==1.19.0
python3 gps_reader.py --port /dev/ttyUSB0 --database ./gps_data.db
```

If you prefer auto-detection, omit `--port`.

### 5. Verify That Data Is Being Written

Open the SQLite database:

```bash
sqlite3 gps_data.db
```

Then run:

```sql
SELECT id, verified, gps_date, gps_time, raw_sentence
FROM gps_data
ORDER BY id DESC
LIMIT 10;
```

## Run With Docker Compose On Raspberry Pi

The provided container setup is intended for a host that has access to the GPS device under `/dev`. The container entrypoint writes daily database files named like `gps_data_YYYY-MM-DD.db` into `/app/data`.

### 1. Review The Compose Volume Path

The current [compose.yaml](/home/brian/PycharmProjects/gps_collector/compose.yaml) maps:

```yaml
volumes:
  - /home/crusader/gps/db:/app/data
  - /dev:/dev
```

Update `/home/crusader/gps/db` to a real directory on your Raspberry Pi if needed.

For example:

```bash
mkdir -p /home/pi/gps/db
```

Then change the compose file to use that directory.

### 2. Build And Start The Container

```bash
docker compose up --build -d
```

### 3. Check Logs

```bash
docker compose logs -f gps_reader
```

### 4. Inspect The Database Files

On the Raspberry Pi host, the database files will be written to the host directory you mapped to `/app/data`.

Example:

```bash
ls /home/pi/gps/db
```

## Notes

- The script currently uses a fixed baud rate of `9600`.
- Valid `GGA`, `RMC`, and `GSA` messages are marked as verified.
- Unrecognized or invalid sentences are still stored, but with `verified = false`.
- The Docker Compose service runs with `privileged: true` and mounts `/dev` so the container can access USB serial devices.
