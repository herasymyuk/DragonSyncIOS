import numpy as np
import zmq
import time
import datetime
import threading

# === CONFIG === #
FREQ_LIST = list(range(870_000_000, 928_000_001, 3_000_000))
SAMPLE_RATE = 2_500_000
THRESHOLD_DB = -45
RECORD_SEC = 5
ZMQ_ADDRESS = "tcp://127.0.0.1:5556"

# === ZMQ INIT === #
ctx = zmq.Context()
sock = ctx.socket(zmq.PUB)
sock.connect(ZMQ_ADDRESS)

# === LOG FUNCTION === #
def log(msg):
    now = datetime.datetime.utcnow().strftime("%H:%M:%S")
    print(f"[{now}] {msg}")

# === MAIN SCAN LOOP === #
def scan_loop():
    log("ZALA/Orlan TUI Scanner started")
    log(f"Frequencies: {len(FREQ_LIST)} total")

    for freq in FREQ_LIST:
        log(f"[SCAN] {freq/1e6:.1f} MHz")
        # Simulated RSSI level
        rssi = np.random.uniform(-70, -30)
        if rssi > THRESHOLD_DB:
            log(f"[DETECT] Signal detected at {freq/1e6:.1f} MHz | RSSI: {rssi:.2f} dB")
            payload = {
                "type": "signal_detected",
                "freq": freq,
                "rssi": round(rssi, 2),
                "timestamp": datetime.datetime.utcnow().isoformat(),
            }
            sock.send_json(payload)
        time.sleep(0.5)

    log("Scan completed.")

# === RUN === #
if __name__ == "__main__":
    log("Initializing scan thread")
    threading.Thread(target=scan_loop, daemon=True).start()
    while True:
        time.sleep(1)
