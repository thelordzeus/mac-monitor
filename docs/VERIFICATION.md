# Dashboard verification

The release passed 17 comparisons against independent macOS counters, along with controlled workloads and regression checks. The public documentation summarizes the method and corrections; raw machine measurements stay local and are excluded from Git.

## Independent checks

| Reading | Reference |
| --- | --- |
| System CPU usage | Independent Mach CPU tick query in Python |
| Physical RAM and core count | `sysctl` |
| App, wired, compressed, cached, free and used RAM | `vm_stat`; Activity Monitor inspected directly |
| Disk capacity and free space | `df` |
| Physical disk read/write rates | Whole-device byte deltas from `ioreg` |
| Physical-interface download/upload rates | Byte deltas from `netstat` |
| A busy single-thread process | `top` measuring the same controlled process |
| Internal battery presence | `pmset` |

Live measurements use nearby sampling windows. Exact equality is required for capacities and core counts. Changing values use tolerances recorded in the local audit output. The audit's network-rate tolerance has a 2 KiB/s floor; a separate known-payload workload checks per-app network accounting more strictly.

## Controlled workloads and regression checks

- Busy single-thread CPU workload: agrees with `top`. The normal dashboard divides one-core usage by the Mac's logical core count; the one-core preference intentionally uses Activity Monitor's scale.
- A process touching 256 MiB RAM: footprint must cover the allocation plus bounded process overhead.
- An 8 MiB local TCP stream: per-app accounting records exactly 8,388,608 sent bytes and 8,388,608 received bytes. The endpoints remain open until the next `nettop` sample. Loopback traffic intentionally does not contribute to physical-interface totals.
- An 8 MiB flushed temporary-file write: process disk accounting records exactly 8,388,608 bytes. The test removes its file afterwards.
- Unequal-duration CPU samples (40% for 1 second, 80% for 3 seconds): 70% before and after saving. Adding 10% for 2 seconds produces 50% when saved and pending points are combined.
- GPU and app-memory history use time weights. Unavailable app GPU/power history stays unavailable.
- Top App ignores table pins/search. App totals, process rows and CPU history share the selected CPU scale.
- Pausing resets rate baselines; resuming establishes a new baseline. Unobserved gaps do not enter totals or idle classification.
- PID identity/protection, process-group uniqueness and formatting checks passed.

## Corrections included

1. Include RAM reserved outside VM page categories in Memory Used. Keep true free RAM separate from cache; label their combined amount Available.
2. Keep speculative pages disjoint from free memory. Apple's [VM statistics definitions](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h) and [vm_stat implementation](https://github.com/apple-oss-distributions/system_cmds/blob/main/vm_stat/vm_stat.c) establish these counter semantics.
3. Include pending samples in today's CPU average and weight app/GPU/battery history by observed duration.
4. Prevent pins/search from changing Top App; correct the app CPU chart/process-row scale.
5. Preserve unavailable GPU/power history, use the chosen history range for GPU averages/peaks, label historical peaks Peak avg, and display app power history in watts.
6. Reset baselines after pause or long sampling gaps; integrate rates with monotonic elapsed time.
7. Label app power as CPU power and process counts as visible processes.

## Limits

GPU utilization and graphics memory come from the graphics driver. App GPU time is a driver estimate; overlapping work can exceed 100%. Live peaks are maxima of sampled readings. Historical points are minute averages, so Peak avg is the highest saved minute average and Average is the mean of those points.

Temperature and fan readings come from the SMC. Their source and availability were checked; their absolute physical accuracy was not independently calibrated. Full battery charge, health, cycle and power validation requires a MacBook. Bluetooth battery reports depend on the device. Audio output and Bluetooth hardware were not part of the quantitative counter audit.

App power is macOS-attributed CPU energy, rather than total wall power. Apple's [recount documentation](https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md) describes these counters. Protected processes may not be inspectable; visible counts can be lower than Activity Monitor's privileged counts.

App network counters refresh roughly every ten seconds; short-lived connections between polls can be missed. Totals cover observed monitoring time. Earlier saved minute averages cannot be reconstructed retroactively; corrections apply to new readings without erasing existing history.

## Repeat locally

```sh
./scripts/build.sh
"dist/Mac Pulse.app/Contents/MacOS/MacMonitor" --self-test
python3 scripts/verify-metrics.py
```

The live audit writes `artifacts/metrics-audit.json`, which is ignored by Git. Review any failed comparison against its tolerance; a rapidly changing workload is not automatically evidence of a collector defect.
