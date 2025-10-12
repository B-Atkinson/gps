#!/usr/bin/env python3
"""
GPS Data Reader for Raspberry Pi and Windows
Detects GPS USB device, reads NMEA sentences, and stores in SQLite
Cross-platform compatible: Windows 11 and Linux
"""

import serial
import serial.tools.list_ports
import pynmea2
import sqlite3
import time
from platform import system
from datetime import datetime
from typing import Optional, List
import argparse

from serial.tools.list_ports_common import ListPortInfo


class GPSReader:
    def __init__(self, db_path: str = 'gps_data.db'):
        self.db_path = db_path
        self.serial_port = None
        self.os_type = system()  # 'Windows', 'Linux', 'Darwin'
        print(f"Detected OS: {self.os_type}")
        self.init_database()

    def init_database(self):
        """Initialize SQLite database with GPS data table"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute(
            '''
            CREATE TABLE IF NOT EXISTS gps_data
            (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                verified     BOOLEAN NOT NULL DEFAULT FALSE,
                gps_date     DATETIME,
                gps_time     DATETIME,
                raw_sentence TEXT
            );'''
        )

        conn.commit()
        conn.close()

    def detect_gps_port(self) -> Optional[str]:
        """
        Detect GPS device on USB ports (cross-platform)
        Returns the port path if found, None otherwise

        Windows: COMx (e.g., COM3, COM4)
        Linux: /dev/ttyUSBx or /dev/ttyACMx
        """
        ports = serial.tools.list_ports.comports()

        print(f"\n{'=' * 60}")
        print(f"Scanning for GPS devices on {self.os_type}...")
        print(f"{'=' * 60}")
        print(f"Available serial ports ({len(ports)} found):\n")

        for port in ports:
            print(f"  Port: {port.device}")
            print(f"    Description: {port.description}")
            print(f"    Manufacturer: {port.manufacturer}")
            print(f"    VID:PID: {port.vid}:{port.pid}")
            print(f"    Serial Number: {port.serial_number}")
            print()

        # Common GPS device identifiers (case-insensitive)
        gps_keywords = ['gps', 'gnss', 'nmea', 'u-blox', 'ublox', 'prolific', 'ch340',
                        'cp210', 'ftdi', 'pl2303', 'globalsat', 'garmin']

        # Try to find GPS device by description/manufacturer
        for port in ports:
            desc_lower = (port.description or '').lower()
            mfg_lower = (port.manufacturer or '').lower()

            if any(
                keyword in desc_lower or keyword in mfg_lower
                for keyword in gps_keywords
            ):
                print(f"GPS device auto-detected at: {port.device}")
                print(f"  ({port.description})")
                return port.device

        # Platform-specific fallback logic
        if self.os_type == 'Windows':
            # On Windows, look for COM ports (usually COM3 and higher for USB devices)
            com_ports = [p for p in ports if 'COM' in p.device]
            # if com_ports:
            #     print(f"⚠ No GPS auto-detected. Using first COM port: {com_ports[0].device}")
            #     return com_ports[0].device
            return com_ports

        elif self.os_type == 'Linux':
            # On Linux, prefer ttyUSB or ttyACM devices
            usb_ports = [p for p in ports if 'ttyUSB' in p.device or 'ttyACM' in p.device]
            # if usb_ports:
            #     print(f"⚠ No GPS auto-detected. Using first USB serial port: {usb_ports[0].device}")
            #     return usb_ports[0].device
            return usb_ports

        # If still nothing found, use first available port
        if ports:
            # print(f"⚠ No GPS auto-detected. Using first available port: {ports[0].device}")
            # return ports[0].device
            return ports

        print("✗ No serial ports found!")
        return None

    def _check_ports(self, ports: List[ListPortInfo], baudrate: int = 9600):
        """Test each port to see if it outputs valid NMEA sentences"""
        for port_info in ports:
            port_device = port_info.device
            temp_serial = None

            try:
                print(f"Testing port {port_device}...")
                temp_serial = serial.Serial(
                    port=port_device,
                    baudrate=baudrate,
                    timeout=1,
                    bytesize=serial.EIGHTBITS,
                    parity=serial.PARITY_NONE,
                    stopbits=serial.STOPBITS_ONE
                )

                start_time = time.time()

                while (time.time() - start_time) < 2.0:
                    if temp_serial.in_waiting:
                        line = temp_serial.readline().decode('ascii', errors='ignore').strip()

                        if line.startswith('$'):
                            try:
                                pynmea2.parse(line)
                                print(f"✓ Valid NMEA data found on {port_device}")
                                # Keep this connection open and store it
                                self.serial_port = temp_serial
                                return port_device
                            except pynmea2.ParseError:
                                # Not valid NMEA, try next port
                                break

                # No valid NMEA found, close and try next port
                if temp_serial and temp_serial.is_open:
                    temp_serial.close()

            except Exception as e:
                print(f"Error testing {port_device}: {e}")
                if temp_serial and temp_serial.is_open:
                    temp_serial.close()

        return None


    def connect(self, port: Optional[str] = None, baudrate: int = 9600) -> bool:
        """
        Connect to GPS device
        Common baudrates: 4800, 9600, 38400, 57600, 115200
        """
        if port is None:
            port = self.detect_gps_port()

        if port is None:
            print("No serial port found!")
            return False

        # If we got a list of ports, test each one
        elif isinstance(port, list):
            port = self._check_ports(port, baudrate)
            if not port:
                print("No GPS device found on any port!")
                return False
            # self.serial_port is already set by _check_ports
            print(f"Connected to {port} at {baudrate} baud")
            return True

        # Single port specified
        try:
            self.serial_port = serial.Serial(
                port=port,
                baudrate=baudrate,
                timeout=1,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE
            )
            print(f"Connected to {port} at {baudrate} baud")
            return True
        except serial.SerialException as e:
            print(f"Error connecting to {port}: {e}")
            return False

    def read_and_parse(self, duration: Optional[int] = None):
        """
        Read and parse NMEA sentences from GPS
        duration: seconds to read (None = infinite)
        """
        if not self.serial_port or not self.serial_port.is_open:
            print("Serial port not connected!")
            return

        start_time = time.time()
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        continue_looping = True

        print("Reading GPS data... (Press Ctrl+C to stop)")

        try:
            while True:
                if duration and (time.time() - start_time) > duration:
                    break

                # Read line from serial port
                if self.serial_port.in_waiting:
                    line = self.serial_port.readline().decode('ascii', errors='ignore').strip()

                    if line.startswith('$'):
                        try:
                            msg = pynmea2.parse(line)
                            self.process_message(msg, line, cursor)
                            conn.commit()
                        except pynmea2.ParseError as e:
                            print(f"Parse error: {e}")
                        except Exception as e:
                            print(f"Error processing message: {e}")

        except KeyboardInterrupt:
            print("\nStopping GPS reader...")
            continue_looping = False
        except Exception as e:
            print(f"Error reading GPS data: {e}")
        finally:
            conn.close()

        return continue_looping

    def process_message(self, msg, raw_sentence: str, cursor):
        """Process different types of NMEA messages"""

        # GGA - Global Positioning System Fix Data
        # https://docs.novatel.com/OEM7/Content/Logs/GPGGA.htm
        if isinstance(msg, pynmea2.GGA) and msg.is_valid:
            print(
                f"GGA: Lat={msg.latitude:.6f}, Lon={msg.longitude:.6f}, "
                f"Alt={msg.altitude}m, Sats={msg.num_sats}, Time={msg.timestamp:%H:%M:%S}"
            )
            gps_t = f"{msg.timestamp:%H:%M:%S}"

            cursor.execute(
                '''
                INSERT INTO gps_data
                    (gps_time, verified, raw_sentence)
                VALUES (?, ?, ?)
                ''', (
                    gps_t, True, raw_sentence
                )
            )

        # RMC - Recommended Minimum Navigation Information
        # https://docs.novatel.com/OEM7/Content/Logs/GPRMC.htm
        elif isinstance(msg, pynmea2.RMC) and msg.is_valid:
            print(
                f"RMC: Lat={msg.latitude:.6f}, Lon={msg.longitude:.6f}, "
                f"Speed={msg.spd_over_grnd} knots, Course={msg.true_course}°, Date={msg.datetime:%d/%m/%Y}, Time={msg.datetime:%H:%M:%S}"
            )
            date = f"{msg.datetime:%d/%m/%Y}"
            gps_t = f"{msg.datetime:%H:%M:%S}"

            cursor.execute(
                '''
                INSERT INTO gps_data
                (gps_date, gps_time, verified, raw_sentence)
                VALUES (?, ?, ?, ?)
                ''', (
                    date, gps_t, True, raw_sentence
                )
            )

        # GSA - GPS DOP and active satellites
        # https://docs.novatel.com/OEM7/Content/Logs/GPGSA.htm
        elif isinstance(msg, pynmea2.GSA) and msg.is_valid:
            print(f"GSA: HDOP={msg.hdop}, VDOP={msg.vdop}, PDOP={msg.pdop}")
            cursor.execute(
                '''
                INSERT INTO gps_data
                    (verified, raw_sentence)
                VALUES (?, ?)''', (True, raw_sentence)
            )

        else:
            cursor.execute(
                '''
                INSERT INTO gps_data
                    (verified, raw_sentence)
                VALUES (?, ?)''', (False, raw_sentence)
            )

    def close(self):
        """Close serial connection"""
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            print("Serial port closed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--database", help="Full database path.", type=str, default="gps_data.db")
    parser.add_argument("-p", "--port", help="Serial port.", type=str, default=None)
    args = parser.parse_args()
    continue_looping = True

    while continue_looping:
        try:
            gps = GPSReader(db_path=args.database)

            print(f"\n{'=' * 60}")
            print(f"GPS Data Logger - Running on {gps.os_type}")
            print(f"{'=' * 60}\n")

            if args.port is not None and gps.connect(port=args.port, baudrate=9600):
                continue_looping = gps.read_and_parse()
            elif gps.connect(baudrate=9600):
                continue_looping = gps.read_and_parse()
            else:
                print("No serial port found!")
                break

        except Exception:
            pass
        finally:
            try:
                gps.close()
            except Exception:
                pass


if __name__ == '__main__':
    main()
