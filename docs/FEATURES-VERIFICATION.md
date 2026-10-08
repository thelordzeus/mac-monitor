# Mac Pulse 1.5.0 verification

These are historical checks for 1.5.0. Insights and Connectivity were removed in 1.5.2; the remaining alert rules and storage tools continue to use their verified core behavior.

Validated on an Apple M4 Mac on 8 October 2026. The screenshots use real readings and scan results. The floating dashboard image comes from the app's renderer with live samples.

## Automated checks

- `./scripts/test-cleanup.sh`: 130 tests in 18 suites completed successfully; 127 executed and passed, and three optional FFmpeg tests were skipped because FFmpeg was unavailable.
- The new tests cover sleep/pause gaps, app restarts, sustained observations, memory-growth windows, cooldowns, unknown sensors, app selection and overnight quiet hours.
- Storage checks cover allocated sizes, hard-link deduplication, skipped symlinks, scan limits, complete/partial comparisons, retention and storage-map area proportions. Network checks cover host validation and ping-result parsing.
- Cleanup tests cover exact bundle-ID matching, changed app files, recorded Trash identity, successful restore in controlled fixtures, destination conflicts, replaced items, changed parents, symlinked parents, missing items, untracked receipts and compatibility with older history.
- The release executable's `--self-test` passed controlled CPU, memory, TCP and disk workloads, plus the existing grouping, PID, pause, history, unavailable-reading, ranking and formatting checks. The CPU worker measured 82.3% of one core, the 256 MiB allocation measured a 258 MB footprint, TCP totals were within one byte of 8 MiB and disk writes measured 8 MiB.

## Native application checks

- Insights reported sustained elevated memory pressure and linked to the Memory view. One observed self-usage reading was 0.4% whole-Mac CPU and 113 MB RAM; this is an observation, not a performance benchmark.
- Two complete scans of the source folder measured 283 kB allocated: MacMonitor 238 kB, SystemBridge 25 kB and PulseCore 20 kB. The comparison correctly reported no measured size changes. The verification-only tracked folder was subsequently removed from preferences.
- Connectivity resolved `apple.com` to `17.253.144.10`, measured 46.2 ms average ping with 0% loss over five probes, and returned HTTP 200 from Apple's HTTPS connectivity endpoint. Checks ran only after pressing Run checks.
- Alert Settings exposed metric, app, threshold and duration controls. Quiet hours displayed 22:00–08:00; notifications remained disabled during verification.
- Inventory's app-file review found the VLC bundle and exact associated paths. Only the app bundle started selected. The final removal confirmation was canceled; VLC and its data were untouched.
- Browse moved a generated disposable file to Trash and recorded its original path, Trash identity, selected size and zero immediate free-space gain. The native restore attempt was blocked by macOS access to the protected Trash directory; the app displayed the Full Disk Access explanation and left the item untouched. Successful restoration and conflict guards were verified with controlled filesystem fixtures, rather than by granting additional permissions on this Mac.
- Menu Bar settings exposed independent item and floating dashboard switches and retained their values. Temporary verification preferences were returned to their prior state. The compact floating view was rendered with live CPU, memory, disk, network and GPU readings; a desktop Mac correctly shows no internal battery.

## Limits

Full Disk Access was not granted during these checks. Restore from protected locations still depends on macOS permissions. Notification delivery during quiet hours was checked in the rule tests; no OS notification was sent. Menu-bar dragging and floating-panel movement across multiple displays were not exercised by the UI automation. Per-app audio mixing, Intel Macs, every hardware sensor and all external volumes remain outside this verification.
