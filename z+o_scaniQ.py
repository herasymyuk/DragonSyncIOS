
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
PATTERN_HEX = 0xF17C1599
PATTERN_BITS = np.unpackbits(np.array(list(PATTERN_HEX.to_bytes(4, 'big')), dtype=np.uint8))
ZMQ_ADDRESS = "tcp://127.0.0.1:5556"
STATION_LAT = 50.4501
STATION_LON = 30.5234
DRIVER = "plutosdr"  # 🔧 Ось тут вказано драйвер

# === ZMQ INIT === #
ctx = zmq.Context()
sock = ctx.socket(zmq.PUB)
sock.connect(ZMQ_ADDRESS)

# === DETECT PATTERN === #
def detect_pattern(samples):
    angle_diff = np.angle(samples[1:] * np.conj(samples[:-1]))
    bits = (angle_diff > 0).astype(np.uint8)
    bits_str = ''.join(map(str, bits))
    pattern_str = ''.join(map(str, PATTERN_BITS))
    return pattern_str in bits_str

# === LOG === #
def log(msg):
    now = datetime.datetime.utcnow().strftime("%H:%M:%S")
    print(f"[{now}] {msg}")

# === MAIN === #
def scan_loop():
    import SoapySDR
    from SoapySDR import SOAPY_SDR_RX, SOAPY_SDR_CF32

    log("Scanner initializing")
    sdr = SoapySDR.Device(dict(driver=DRIVER))
    sdr.setSampleRate(SOAPY_SDR_RX, 0, SAMPLE_RATE)
    sdr.setGain(SOAPY_SDR_RX, 0, 40)
    stream = sdr.setupStream(SOAPY_SDR_RX, SOAPY_SDR_CF32)

    log("Scanning...")
    for freq in FREQ_LIST:
        log(f"[SCAN] {freq/1e6:.1f} MHz")
        sdr.setFrequency(SOAPY_SDR_RX, 0, freq)
        sdr.activateStream(stream)

        buff = np.array([0]*1024, np.complex64)
        sr = sdr.readStream(stream, [buff], len(buff))
        log(f"  sr.ret = {sr.ret}")

        if sr.ret > 0:
            power_db = 10 * np.log10(np.mean(np.abs(buff[:sr.ret])**2) + 1e-12)
            if power_db > THRESHOLD_DB:
                now = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
                fname = f"iq_{int(freq/1e6)}MHz_{now}.cu8"
                samples_total = int(RECORD_SEC * SAMPLE_RATE)
                recorded = np.zeros(samples_total, dtype=np.complex64)

                idx = 0
                while idx < samples_total:
                    sr = sdr.readStream(stream, [buff], len(buff))
                    if sr.ret > 0:
                        recorded[idx:idx+sr.ret] = buff[:sr.ret]
                        idx += sr.ret

                recorded.tofile(fname)
                log(f"[SAVE] {fname}")

                pattern_found = detect_pattern(recorded[:4096])
                if pattern_found:
                    log("[MATCH] Signature 0xF17C1599 found")

                payload = {
                    "type": "signal_detected",
                    "freq": freq,
                    "rssi": round(power_db, 2),
                    "timestamp": now,
                    "pattern": pattern_found,
                    "lat": STATION_LAT,
                    "lon": STATION_LON
                }
                sock.send_json(payload)

                with open("cav.log", "a") as logf:
                    log_line = f"{now} | {freq/1e6:.1f} MHz | {power_db:.2f} dB | pattern={pattern_found} | lat={STATION_LAT} | lon={STATION_LON}\n"
                    logf.write(log_line)

        sdr.deactivateStream(stream)
        time.sleep(1)

    log("Scan complete.")

if __name__ == "__main__":
    threading.Thread(target=scan_loop, daemon=True).start()
    while True:
        time.sleep(1)
