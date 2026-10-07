# Mac Monitor

A native macOS dashboard for seeing what your Mac is doing. Monitor CPU, memory, GPU, disks, network traffic, battery, audio, Bluetooth devices and development projects in one dark interface.

Built with SwiftUI, AppKit, C and Objective-C. All readings come from the Mac. No account, telemetry, cloud service, external package dependencies or web server is required.

![Mac Monitor overview with live system cards, history charts and memory breakdowns](artifacts/screenshots/overview.png)

## Download and install

**[Download for Mac — DMG](https://github.com/thelordzeus/mac-monitor/releases/latest/download/Mac-Monitor-arm64.dmg)**

[ZIP download](https://github.com/thelordzeus/mac-monitor/releases/latest/download/Mac-Monitor-arm64.zip) · [Release notes](https://github.com/thelordzeus/mac-monitor/releases/latest) · [SHA256 checksums](https://github.com/thelordzeus/mac-monitor/releases/latest/download/SHA256SUMS)

The DMG and ZIP contain the same app. The release includes `SHA256SUMS` for checking downloaded files.

**Requirements:** an Apple Silicon Mac (M1 or later) running **macOS 14.2 or newer**. The published binary is `arm64`. Intel users can try building from source on an Intel Mac; that configuration has not been tested.

1. Download and open `Mac-Monitor-arm64.dmg`.
2. Drag **Mac Monitor.app** to the **Applications** folder shown in the disk image.
3. Eject the disk image and open **Mac Monitor** from Applications.
4. The dashboard starts collecting readings. Click its menu-bar icon for a compact view; click anywhere outside the panel to dismiss it.

The downloadable build is signed locally (**ad hoc**) and is **not notarized by Apple**. If macOS blocks the first launch, review the source and download, then approve this specific app in **System Settings → Privacy & Security → Open Anyway**. See [Apple's first-launch instructions](https://support.apple.com/102445).

To verify a download, run `shasum -a 256 Mac-Monitor-arm64.dmg` and compare its result with the matching entry in the release's `SHA256SUMS` file.

## Features

| Tab | What you can see or do |
| --- | --- |
| **Overview** | Six live metric cards, recent bar charts, memory breakdowns, app memory and app CPU energy. CPU/GPU temperatures, fan speeds and thermal state appear when available. |
| **CPU** | Total, user and system usage, load average, core count, app rankings and individual processes. |
| **Memory** | App, wired, compressed, reserved, cached, free and swap memory, available memory, pressure and grouped app footprints. |
| **Disk** | Free/used capacity, mounted volumes, physical read/write rates and app writes. |
| **Network** | Download/upload rates, current interface, app traffic and totals observed while monitoring. |
| **GPU** | Driver utilization, graphics memory, app GPU time, recent average and peak. |
| **Battery** | Charge, estimated time, cycles, health, temperature and power draw on supported Macs. |
| **Sound** | Choose an output, adjust supported system volume, see playing/silent status, and adjust or mute each app through Core Audio process taps. |
| **Bluetooth** | Connected/paired devices and reported battery levels, including earbud/case readings when macOS supplies them. |
| **Projects** | Runtimes grouped by working directory, listening ports, observed CPU inactivity and confirmed process termination. |

Beyond the tabs:

- **Menu bar:** choose live readouts and open a compact dashboard. Monitoring continues when you close the main window; use Quit to stop the app.
- **History:** recent live readings plus 1-hour, 12-hour, 24-hour, 7-day and 30-day ranges. App detail sheets include per-app history.
- **Alerts:** sustained CPU use, memory growth, heavy disk writes and network traffic. System notifications are optional.
- **App controls:** search, pin apps, include system processes, inspect processes and confirm graceful or forced termination.
- **Export:** save/copy a dashboard PNG or export app statistics as CSV.
- **Customization:** reorder/hide tabs, hide overview cards, choose refresh interval, Celsius/Fahrenheit and network bits/bytes, and enable launch at login.

## Screenshots

The images show actual readings from an Apple M4 desktop Mac; screenshot totals use saved local history. The Battery tab correctly reports no internal battery; Bluetooth discovery is shown before the user enables it. Supported readings will differ on your Mac.

| CPU | Memory |
| --- | --- |
| ![CPU usage, recent chart and app rankings](artifacts/screenshots/cpu.png) | ![Memory usage, pressure, component totals and app rankings](artifacts/screenshots/memory.png) |

<details>
<summary>Disk, network and GPU</summary>

### Disk

![Disk capacity, read/write rates and app writes](artifacts/screenshots/disk.png)

### Network

![Network speeds, interface and app traffic](artifacts/screenshots/network.png)

### GPU

![GPU utilization, graphics memory and app GPU time](artifacts/screenshots/gpu.png)

</details>

<details>
<summary>Battery, sound, Bluetooth and projects</summary>

### Battery

![Battery tab on a desktop Mac without an internal battery](artifacts/screenshots/battery.png)

### Sound

![Audio output, playing status and per-app volume sliders](artifacts/screenshots/sound.png)

### Bluetooth

![Bluetooth device discovery and battery panel](artifacts/screenshots/bluetooth.png)

### Projects

![Running development projects and listening ports](artifacts/screenshots/projects.png)

</details>

## Getting started

Click a metric card or a top tab for detail. Click an app row for its processes and history. Use the time ranges at the bottom to inspect saved readings, the pause button to pause collection, the bell for activity alerts, the share button for exports and the gear for settings.

| Shortcut | Action |
| --- | --- |
| `⌘1` through `⌘9`, `⌘0` | Switch tabs in their original order; `⌘0` opens Projects. |
| `⌘,` | Open settings. |
| `⌘⇧P` | Pause/resume monitoring. |
| `⌘⇧E` | Export app statistics. |
| `Esc` | Dismiss the menu-bar panel. |
| `⌘Q` | Quit the app. |

### Optional permissions

- **Per-app audio:** the first app-volume adjustment can request macOS system-audio access. If denied, allow Mac Monitor under **Privacy & Security → Screen & System Audio Recording**, then relaunch. Audio is processed in memory. Normal monitoring and supported system-volume controls do not capture audio.
- **Bluetooth:** click **Read Bluetooth Devices** or Refresh to start discovery. Devices that do not report battery levels show **Not reported**.
- **Notifications:** enable them in the app's settings. They are off by default.
- **Launch at login:** enable it in settings. macOS may require approval in Login Items.

## Build from source

Clone this repository, then run these commands from its root:

```sh
git clone https://github.com/thelordzeus/mac-monitor.git
cd mac-monitor
./scripts/build.sh
./scripts/run.sh
```

The build script compiles a release executable, creates `dist/Mac Monitor.app`, adds the icon and signs the bundle locally. It uses `/Applications/Xcode.app` when available, otherwise the selected Command Line Tools. SDKs requiring SwiftUI macro plugins, including macOS 27, need **full Xcode**. No paid developer account is needed for this local build. The executable targets the architecture of the machine compiling it.

### Create a DMG and ZIP

```sh
./scripts/package.sh
```

The script builds the app and creates architecture-specific DMG/ZIP files plus `dist/SHA256SUMS`. The DMG includes the app, an Applications shortcut and installation notes. If you already built the current source, use `./scripts/package.sh --skip-build`.

Built artifacts stay in `dist/` and are excluded from Git. Publish the DMG, ZIP and checksums as GitHub Release assets rather than committing binaries.

## How readings and history work

Metrics are sampled locally, every two seconds by default. A dash means macOS or the hardware did not supply a reading.

History is stored in `~/Library/Application Support/MacMonitor/history.sqlite`. It saves minute averages, flushes on normal exit and retains 30 days. It starts when you run the app. Periods when monitoring is paused, the Mac is sleeping or the app has quit are not observed. Nothing is uploaded.

- App CPU is normalized across the Mac by default; settings can switch to percentages of one core.
- App memory uses physical footprint when available. Shared memory means summed app footprints can differ from system memory. RAM uses binary units; disk capacity and network traffic use decimal units.
- Memory Used includes system-reserved RAM and excludes free pages and reclaimable cache. Available includes both free RAM and cache. The breakdown keeps these categories separate.
- App GPU time comes from driver counters. Overlapping work can exceed 100%.
- App power is macOS-reported **CPU energy**, rather than whole-system power. Battery watts come from current and voltage; values while on AC can be zero.
- Network totals cover observed periods. System counters use physical `en*` and cellular interfaces. App network counters refresh roughly every ten seconds through `nettop` and can be restricted by macOS.
- Project inactivity reflects observed CPU usage, rather than whether a server handled a request recently.

## Limits

Sensor and device support varies by Mac. Manual fan control, a full localization set and independent draggable menu-bar items are not included. Selected menu-bar readings share one movable item. Some protected processes cannot be fully inspected or terminated without further privileges.

The build and core statistics/history checks were validated on an Apple M4 Mac. Per-app audio mixing is implemented but has not been tested end to end. Intel Macs and every possible battery/Bluetooth device have not been tested.

## Development checks

```sh
"dist/Mac Monitor.app/Contents/MacOS/MacMonitor" --self-test
"dist/Mac Monitor.app/Contents/MacOS/MacMonitor" --diagnostics
python3 scripts/verify-metrics.py
"dist/Mac Monitor.app/Contents/MacOS/MacMonitor" --render artifacts/screenshots
```

The self-test checks controlled CPU, 256 MiB memory, 8 MiB TCP and 8 MiB disk workloads, PID grouping, stale-PID protection, pause baselines, weighted history, pending totals, unknown readings, app ranking and formatting. The independent Python audit compares live readings with macOS counters and commands, saving a local report to `artifacts/metrics-audit.json` (excluded from Git). See [the verification findings](docs/VERIFICATION.md) for results and limitations. `--render` produces all ten screenshots from real Mac readings; it does not inject simulated statistics.

## Design reference

The interface is inspired by [Vitals](https://vitalsmac.com/). Mac Monitor is an independent implementation with its own name, icon and source code and is not affiliated with Vitals.
