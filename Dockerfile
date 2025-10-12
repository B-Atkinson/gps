FROM ubuntu:latest
LABEL authors="brian atkinson"

ENV DEBIAN_FRONTEND=noninteractive

# OS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    sqlite3 libsqlite3-0 \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create and activate a dedicated venv for app deps
RUN python3 -m venv /opt/venv
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Install Python deps into the venv (no PEP 668 issues)
RUN pip install --no-cache-dir \
    pynmea2==1.19.0 \
    pyserial==3.5

# App files & dirs
RUN mkdir -p /app/data /app/src
COPY compose.yaml /app/src/compose.yaml
COPY gps_reader.py /app/src/gps_reader.py
WORKDIR /app/src

# Use bash so $(date) expands at *container runtime*
ENTRYPOINT ["/bin/bash","-c","python gps_reader.py -d \"/app/data/gps_data_$(date +%Y-%m-%d).db\""]
