"""Host-only process faults; never imports or runs an inference runtime."""
import json
import os
import signal
import sys
import time

mode, binding, case = sys.argv[1:]

def record(event, sequence):
    return {"schema": 1, "binding": binding, "case_id": case,
            "pid": os.getpid(), "sequence": sequence, "event": event}

print(json.dumps(record("started", 0)), flush=True)
sys.stderr.buffer.write(b"raw-native-stderr\x00\xff\n")
sys.stderr.buffer.flush()
if mode == "hang":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(30)
elif mode == "overflow":
    sys.stdout.write("x" * 65536)
    sys.stdout.flush()
elif mode == "truncated":
    sys.stdout.write('{"unfinished":')
    sys.stdout.flush()
elif mode == "wrong-binding":
    value = record("finished", 1)
    value["binding"] = "f" * 64
    print(json.dumps(value), flush=True)
elif mode == "failure":
    sys.exit(7)
else:
    print(json.dumps(record("finished", 1)), flush=True)
