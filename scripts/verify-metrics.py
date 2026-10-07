#!/usr/bin/env python3
"""Compare the built collector with independent macOS commands (no dependencies).

No personal process names, addresses or paths are saved in the report. Live
comparisons use nearby sampling windows; tolerances accommodate their offsets.
"""
import ctypes
import datetime
import json
import pathlib
import platform
import plistlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
with (ROOT / "Resources/Info.plist").open("rb") as app_info:
    APP_INFO = plistlib.load(app_info)
APP = ROOT / "dist" / (APP_INFO["CFBundleDisplayName"] + ".app") / "Contents/MacOS" / APP_INFO["CFBundleExecutable"]
MIB = 1024 ** 2
results = []


def command(*args):
    return subprocess.check_output(args, timeout=15).decode()


def check(name, measured, reference, tolerance=0, note=""):
    passed = abs(measured - reference) <= tolerance
    results.append(dict(metric=name, measured=measured, reference=reference,
                        tolerance=tolerance, passed=passed, note=note))
    print(f"{'PASS' if passed else 'REVIEW'} {name}: app={measured:.3f}, reference={reference:.3f}", flush=True)


LIB = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
LIB.mach_host_self.restype = ctypes.c_uint32
LIB.host_statistics.argtypes = [ctypes.c_uint32, ctypes.c_int,
                               ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32)]


def cpu_ticks():
    ticks = (ctypes.c_uint32 * 4)()
    count = ctypes.c_uint32(4)
    host = LIB.mach_host_self()
    status = LIB.host_statistics(host, 3, ticks, ctypes.byref(count))
    LIB.mach_port_deallocate(ctypes.c_uint32.in_dll(LIB, "mach_task_self_").value, host)
    if status:
        raise RuntimeError(f"Independent host_statistics failed: {status}")
    return list(ticks)


def network_bytes():
    incoming = outgoing = 0
    for line in command("/usr/sbin/netstat", "-ibn").splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 10 and fields[2].startswith("<Link#") and fields[0].startswith(("en", "pdp_ip")):
            incoming += int(fields[-5])
            outgoing += int(fields[-2])
    return incoming, outgoing


def disk_bytes():
    drivers = plistlib.loads(subprocess.check_output(
        ["/usr/sbin/ioreg", "-a", "-r", "-c", "IOBlockStorageDriver", "-d", "1"], timeout=15))
    return tuple(sum(driver.get("Statistics", {}).get(key, 0) for driver in drivers)
                 for key in ("Bytes (Read)", "Bytes (Write)"))


def counters():
    # Read CPU immediately after receipt of the collector's JSON line.
    ticks = cpu_ticks()
    stamp = time.monotonic()
    return stamp, ticks, network_bytes(), disk_bytes()


def memory_bytes():
    text = command("/usr/bin/vm_stat")
    page = int(re.search(r"page size of (\d+)", text)[1])
    pages = {key: int(value) for key, value in re.findall(r"^(.+?):\s+(\d+)\.", text, re.M)}
    return {
        "memoryApp": (pages["Anonymous pages"] - pages["Pages purgeable"]) * page,
        "memoryWired": pages["Pages wired down"] * page,
        "memoryCompressed": pages["Pages occupied by compressor"] * page,
        "memoryCached": (pages["File-backed pages"] + pages["Pages purgeable"]) * page,
        # vm_stat already subtracts speculative pages from its free-page row.
        "memoryFree": pages["Pages free"] * page,
    }


def main():
    if platform.system() != "Darwin":
        raise RuntimeError("This audit requires macOS.")
    if not APP.exists():
        raise RuntimeError("Build the app with ./scripts/build.sh first.")
    worker = subprocess.Popen([str(APP), "--cpu-worker"], stdout=subprocess.DEVNULL)
    top = subprocess.Popen(["/usr/bin/top", "-l", "3", "-s", "2", "-pid", str(worker.pid),
                            "-stats", "pid,command,cpu,mem"], stdout=subprocess.PIPE, text=True)
    monitor = subprocess.Popen([str(APP), "--diagnostics", "--stream", "--samples", "3",
                                "--sample-interval", "2"], stdout=subprocess.PIPE, text=True)
    try:
        observations = []
        for index in range(3):
            line = monitor.stdout.readline()
            if not line:
                raise RuntimeError("Collector exited without the expected JSON samples.")
            snapshot = json.loads(line)
            if index > 0:
                observations.append((snapshot, counters()))
        monitor.wait(timeout=15)
        app, last = observations[-1]
        _, first = observations[0]
        dt = last[0] - first[0]
        deltas = [(end - start) % (2 ** 32) for start, end in zip(first[1], last[1])]
        busy = 100 * (deltas[0] + deltas[1] + deltas[3]) / sum(deltas)
        check("System CPU (percent)", app["cpu"], busy, 3, "Independent Mach query in Python; overlapping windows.")
        for i, name in enumerate(("download", "upload")):
            rate = max(0, last[2][i] - first[2][i]) / dt
            check(name + " (bytes/s)", app[name], rate, max(2048, rate * .08), "netstat physical-interface byte deltas.")
        for i, name in enumerate(("diskRead", "diskWrite")):
            rate = max(0, last[3][i] - first[3][i]) / dt
            check(name + " (bytes/s)", app[name], rate, max(65536, rate * .12), "ioreg whole-device byte deltas.")
        memory = memory_bytes()
        physical = int(command("/usr/sbin/sysctl", "-n", "hw.memsize"))
        check("Physical RAM (bytes)", app["totalMemory"], physical)
        check("Logical cores", app["cores"], int(command("/usr/sbin/sysctl", "-n", "hw.logicalcpu")))
        for name, value in memory.items():
            check(name + " (MiB)", app[name] / MIB, value / MIB, 96, "vm_stat snapshot taken just after collector.")
        used = physical - memory["memoryCached"] - memory["memoryFree"]
        check("Memory used (MiB)", app["memoryUsed"] / MIB, used / MIB, 96)
        df = command("/bin/df", "-k", "/System/Volumes/Data").splitlines()[-1].split()
        check("Disk capacity (bytes)", app["diskTotal"], int(df[1]) * 1024)
        check("Disk free (MiB)", app["diskFree"] / MIB, int(df[3]) * 1024 / MIB, 16)
        top_text, _ = top.communicate(timeout=15)
        top_cpu = [float(match[1]) for match in re.finditer(
            rf"^\s*{worker.pid}\s+\S+\s+([\d.]+)", top_text, re.M)]
        process = next(p for p in app["processReadings"] if p["pid"] == worker.pid)
        if len(top_cpu) < 2:
            raise RuntimeError("top did not return a sampled reading for the CPU worker.")
        check("CPU worker (percent of one core)", process["cpu"], top_cpu[-1], 15,
              "top measures the same controlled process over a nearby two-second window.")
        battery_text = command("/usr/bin/pmset", "-g", "batt")
        check("Internal battery present", int(app["batteryPresent"]), int("InternalBattery" in battery_text))
        report = dict(date=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      macOS=platform.mac_ver()[0], architecture=platform.machine(),
                      comparisons=results,
                      limitations=["Live windows are close, not simultaneous; tolerances are stated.",
                                   "GPU and SMC readings are driver/sensor reports, not independently calibrated.",
                                   "Battery health/cycles require a Mac with an internal battery.",
                                   "Daily totals are observed traffic, not whole-boot or unobserved-period totals."])
        output = ROOT / "artifacts/metrics-audit.json"
        output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Report: {output}")
        return 0 if all(row["passed"] for row in results) else 1
    finally:
        for child in (monitor, top, worker):
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=15)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Audit failed: {error}", file=sys.stderr)
        sys.exit(1)
