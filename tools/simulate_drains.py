"""
Smart Drainage Guard - drain simulator
---------------------------------------
Publishes fake-but-realistic sensor readings to the same MQTT topics the
real node uses, so the dashboard and app can be built and demoed before
(or alongside) the hardware.

It plays a short "storm": rain fills three drains, then they drain.
  D02 drains normally
  D03 is BLOCKED - it rises higher and drains very slowly
  D04 overflows

Install:  pip install paho-mqtt
Run (cloud broker, TLS):
  python simulate_drains.py --host your-broker-host.emqxsl.com --user sdg-sim --password ****
Run (local broker, no TLS):
  python simulate_drains.py --host localhost --port 1883 --no-tls
"""
import argparse
import json
import math
import random
import ssl
import time

import paho.mqtt.client as mqtt

DRAINS = [
    # id, name, max_cm, peak fraction, drain speed (higher = faster)
    ("D02", "Zastron St stormwater inlet", 30.0, 0.62, 1.0),
    ("D03", "Botshabelo Section H catch basin", 30.0, 0.80, 0.12),  # blocked
    ("D04", "Thaba Nchu taxi rank gutter", 25.0, 1.02, 0.6),        # overflows
]


def level_at(t, peak, speed, max_cm):
    """Storm curve: rise for 60 s, then exponential drain. Loops every 6 min."""
    t = t % 360
    if t < 60:
        frac = peak * math.sin((t / 60) * math.pi / 2)
    else:
        frac = peak * math.exp(-speed * (t - 60) / 60)
    frac = max(0.0, frac + random.uniform(-0.01, 0.01))
    return frac * max_cm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=8883)
    ap.add_argument("--user")
    ap.add_argument("--password")
    ap.add_argument("--no-tls", action="store_true")
    ap.add_argument("--every", type=float, default=3.0, help="seconds between readings")
    ap.add_argument("--duration", type=float, default=0, help="stop after N seconds (0 = forever)")
    a = ap.parse_args()

    c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"sdg-sim-{random.randint(0, 9999)}")
    if a.user:
        c.username_pw_set(a.user, a.password)
    if not a.no_tls:
        c.tls_set(cert_reqs=ssl.CERT_REQUIRED)
    c.connect(a.host, a.port, keepalive=30)
    c.loop_start()
    for d in DRAINS:
        c.publish(f"sdg/drain/{d[0]}/status", "online", qos=1, retain=True)

    start = time.time()
    print("Publishing... Ctrl+C to stop")
    try:
        while a.duration == 0 or time.time() - start < a.duration:
            t = time.time() - start
            for did, name, max_cm, peak, speed in DRAINS:
                lvl = level_at(t, peak, speed, max_cm)
                payload = {
                    "id": did, "name": name, "max_cm": max_cm,
                    "level_cm": round(lvl, 1),
                    "pct": round(lvl / max_cm * 100, 1),
                    "float_high": lvl / max_cm > 0.85,
                    "rssi": random.randint(-75, -55),
                    "uptime_s": int(t), "simulated": True,
                }
                c.publish(f"sdg/drain/{did}/level", json.dumps(payload))
                print(did, payload["level_cm"], "cm", f'({payload["pct"]}%)')
            time.sleep(a.every)
    except KeyboardInterrupt:
        pass
    finally:
        for d in DRAINS:
            c.publish(f"sdg/drain/{d[0]}/status", "offline", qos=1, retain=True)
        time.sleep(0.5)
        c.loop_stop()
        c.disconnect()


if __name__ == "__main__":
    main()
