#!/usr/bin/env python3
import serial
import zmq
import socket
import argparse
import struct
import json
import time
import traceback
from datetime import datetime

def setup_zmq_publisher(host, port):
    context = zmq.Context()
    socket = context.socket(zmq.PUB)
    socket.bind(f"tcp://{host}:{port}")
    return socket

def setup_multicast_socket(group, port):
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
        
        print(f"Multicast Socket Details:")
        print(f"Group: {group}")
        print(f"Port: {port}")
        
        return sock
    except Exception as e:
        print(f"Multicast socket setup error: {e}")
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
    args = parser.parse_args()

    print(f"Opening serial port {args.device} at {args.baud} baud...")

    zmq_socket = None
    multicast_socket = None

    if args.zmq:
        print(f"Setting up ZMQ publisher on {args.zmq_host}:{args.zmq_port}")
        zmq_socket = setup_zmq_publisher(args.zmq_host, args.zmq_port)
    if args.multicast:
        print(f"Setting up multicast on group {args.multicast_group}:{args.multicast_port}")
        multicast_socket = setup_multicast_socket(args.multicast_group, args.multicast_port)

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
        
        print(f"Serial port opened successfully: {ser.name}")
        
        while True:
            try:
                line = ser.readline()
                if line:
                    try:
                        line_decoded = line.decode('utf-8', errors='ignore').strip()
                        if line_decoded:  # Only process non-empty lines
                            timestamp = datetime.now().isoformat()
                            print(f"Read: {line_decoded}")
                            
                            message = {
                                "type": "serial",
                                "timestamp": timestamp,
                                "data": line_decoded
                            }
                            
                            if args.zmq and zmq_socket:
                                print(f"Sending via ZMQ: {message}")
                                zmq_socket.send_json(message)
                            
                            if args.multicast and multicast_socket:
                                try:
                                    message_json = json.dumps(message)
#                                   print(f"Attempting Multicast Send:")
#                                   print(f"Group: {args.multicast_group}")
#                                   print(f"Port: {args.multicast_port}")
#                                   print(f"Message: {message_json}")
                                    
                                    bytes_sent = multicast_socket.sendto(
                                        message_json.encode(),
                                        (args.multicast_group, args.multicast_port)
                                    )
                                    print(f"Multicast sent {bytes_sent} bytes")
                                except Exception as multicast_error:
                                    print(f"Multicast send error: {multicast_error}")
                                    traceback.print_exc()
                    except UnicodeDecodeError as e:
                        print(f"Error decoding line: {e}")
                        continue
            except serial.SerialException as e:
                print(f"Serial error: {e}")
                break

    except serial.SerialException as e:
        print(f"Error opening serial port: {e}")
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        print("Cleaning up...")
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print("Serial port closed")
        if zmq_socket:
            zmq_socket.close()
            print("ZMQ socket closed")
        if multicast_socket:
            multicast_socket.close()
            print("Multicast socket closed")

if __name__ == '__main__':
    main()