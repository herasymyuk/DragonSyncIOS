#!/usr/bin/env python3
import serial
import zmq
import socket
import argparse
import struct
import json
import time
import traceback
import os
import sys
import logging
from datetime import datetime

def setup_logging(log_file=None):
    """Set up logging to both console and file if specified"""
    logger = logging.getLogger('serialmonitor')
    logger.setLevel(logging.INFO)
    
    # Create formatter
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    # File handler (if specified)
    if log_file:
        try:
            # Create directory if it doesn't exist
            log_dir = os.path.dirname(log_file)
            if log_dir and not os.path.exists(log_dir):
                os.makedirs(log_dir)
                
            file_handler = logging.FileHandler(log_file)
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        except Exception as e:
            logger.error(f"Failed to set up file logging: {e}")
    
    return logger

def wait_for_device(device_path, logger, timeout=None):
    """Wait for the device to become available with optional timeout"""
    start_time = time.time()
    logger.info(f"Waiting for device: {device_path}")
    
    while True:
        if os.path.exists(device_path):
            logger.info(f"Device {device_path} found")
            return True
        
        if timeout and (time.time() - start_time > timeout):
            logger.error(f"Timeout waiting for device: {device_path}")
            return False
        
        logger.debug(f"Device {device_path} not found, waiting...")
        time.sleep(1)

def setup_zmq_publisher(host, port, logger):
    logger.info(f"Setting up ZMQ publisher on {host}:{port}")
    context = zmq.Context()
    socket = context.socket(zmq.PUB)
    socket.bind(f"tcp://{host}:{port}")
    return socket

def setup_multicast_socket(group, port, logger):
    logger.info(f"Setting up multicast on group {group}:{port}")
    try:
        # Create socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        
        # Enable address reuse
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        # Set multicast TTL
        ttl = struct.pack('b', 1)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)
        
        # Allow multiple processes to bind to the same port
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        
        # Bind to all interfaces
        sock.bind(('', port))
        
        # Join the multicast group
        group_bin = socket.inet_aton(group)
        mreq = struct.pack('4sL', group_bin, socket.INADDR_ANY)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        
        logger.info(f"Multicast socket setup successful")
        return sock
    except Exception as e:
        logger.error(f"Multicast socket setup error: {e}")
        traceback.print_exc()
        return None

def main():
    parser = argparse.ArgumentParser(description='Serial Monitor Service')
    parser.add_argument('--zmq', action='store_true', help='Enable ZMQ output')
    parser.add_argument('--multicast', action='store_true', help='Enable multicast output')
    parser.add_argument('--zmq-host', default='0.0.0.0', help='ZMQ host')
    parser.add_argument('--zmq-port', type=int, default=4227, help='ZMQ port')
    parser.add_argument('--multicast-group', default='224.0.0.1', help='Multicast group')
    parser.add_argument('--multicast-port', type=int, default=6970, help='Multicast port')
    parser.add_argument('--device', default='/dev/ttyUSB1', help='Serial device')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate')
    parser.add_argument('--device-timeout', type=int, default=0, help='Timeout in seconds for device waiting (0 = wait forever)')
    parser.add_argument('--log-file', help='Path to log file', default='/var/log/serialmonitor.log')
    args = parser.parse_args()

    # Setup logging
    logger = setup_logging(args.log_file)
    logger.info("Serial Monitor Service starting...")

    # Wait for device to be available
    timeout = args.device_timeout if args.device_timeout > 0 else None
    if not wait_for_device(args.device, logger, timeout):
        logger.error("Device not found within timeout period. Exiting.")
        return 1

    logger.info(f"Opening serial port {args.device} at {args.baud} baud...")

    zmq_socket = None
    multicast_socket = None

    if args.zmq:
        zmq_socket = setup_zmq_publisher(args.zmq_host, args.zmq_port, logger)
    if args.multicast:
        multicast_socket = setup_multicast_socket(args.multicast_group, args.multicast_port, logger)

    try:
        ser = serial.Serial(
            port=args.device,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False
        )
        
        logger.info(f"Serial port opened successfully: {ser.name}")
        
        while True:
            try:
                line = ser.readline()
                if line:
                    try:
                        line_decoded = line.decode('utf-8', errors='ignore').strip()
                        if line_decoded:  # Only process non-empty lines
                            timestamp = datetime.now().isoformat()
                            logger.info(f"Read: {line_decoded}")
                            
                            message = {
                                "type": "serial",
                                "timestamp": timestamp,
                                "data": line_decoded
                            }
                            
                            if args.zmq and zmq_socket:
                                logger.debug(f"Sending via ZMQ: {message}")
                                zmq_socket.send_json(message)
                            
                            if args.multicast and multicast_socket:
                                try:
                                    message_json = json.dumps(message)
                                    bytes_sent = multicast_socket.sendto(
                                        message_json.encode(),
                                        (args.multicast_group, args.multicast_port)
                                    )
                                    logger.debug(f"Multicast sent {bytes_sent} bytes")
                                except Exception as multicast_error:
                                    logger.error(f"Multicast send error: {multicast_error}")
                                    logger.error(traceback.format_exc())
                    except UnicodeDecodeError as e:
                        logger.error(f"Error decoding line: {e}")
                        continue
            except serial.SerialException as e:
                logger.error(f"Serial error: {e}")
                # Try to reconnect
                logger.info("Attempting to reconnect in 5 seconds...")
                time.sleep(5)
                if not wait_for_device(args.device, logger, 30):  # 30 second timeout for reconnect
                    logger.error("Failed to reconnect to device. Exiting.")
                    break
                try:
                    ser = serial.Serial(
                        port=args.device,
                        baudrate=args.baud,
                        bytesize=serial.EIGHTBITS,
                        parity=serial.PARITY_NONE,
                        stopbits=serial.STOPBITS_ONE,
                        timeout=1,
                        xonxoff=False,
                        rtscts=False,
                        dsrdtr=False
                    )
                    logger.info(f"Reconnected to serial port: {ser.name}")
                except serial.SerialException as e:
                    logger.error(f"Failed to reopen serial port: {e}")
                    break

    except serial.SerialException as e:
        logger.error(f"Error opening serial port: {e}")
    except KeyboardInterrupt:
        logger.info("Exiting by user request (KeyboardInterrupt)...")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        logger.error(traceback.format_exc())
    finally:
        logger.info("Cleaning up...")
        if 'ser' in locals() and ser.is_open:
            ser.close()
            logger.info("Serial port closed")
        if zmq_socket:
            zmq_socket.close()
            logger.info("ZMQ socket closed")
        if multicast_socket:
            multicast_socket.close()
            logger.info("Multicast socket closed")

    return 0

if __name__ == '__main__':
    sys.exit(main())
