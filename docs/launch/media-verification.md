# Launch media and readiness verification

Prepared on 31 October 2026 from Mac Pulse **1.5.2, build 12**, running on an Apple M4 desktop Mac. This is a marketing/documentation update; the app binary, version and update feed are unchanged.

## Capture record

- Native app captures cover Overview, CPU, Cleanup, cache Inventory and Projects. Captures contain actual system readings and the actual local PostgreSQL process; they are not mockups or simulated statistics.
- Inventory was filtered to `Library/Caches`, and the Arc and JetBrains cache rows were selected to demonstrate the count/size footer. The selection was cleared afterward. No final removal action was executed. No personal files were moved, no app was terminated and no project was stopped.
- Overview and project gallery panels crop the original screenshots to show the feature detail. Screenshot values, app names and selections were not changed. The original PNG captures are included under `artifacts/launch/product-hunt/source`.
- The video is a captioned sequence of these real captures, with transitions and a progress line. It is explicitly described as a walkthrough assembled from captures, not a continuous recording. The 2.9 GB selected size is not claimed as reclaimed space.
- The existing app icon supplies the thumbnail. The caption, compatibility and first-launch text are code-rendered with AppKit. No third-party music, generated interface or invented testimonial is included.

## Asset checks

- Five gallery images: **1270×760 PNG** each.
- Thumbnail: **240×240 PNG**.
- Demo: **40 seconds**, **1280×720**, **H.264**, **20 fps**, no audio track.
- All **800 video frames** decoded successfully with increasing timestamps.
- Gallery panels, the thumbnail and sampled video frames were visually inspected. Text is upright, the app captures retain their aspect ratio, and the selected-count footer and compatibility statement remain visible.
- SRT timings match the five scenes: 0–7, 7–14, 14–24, 24–32 and 32–40 seconds.
- The listing tagline is **54 characters** and the description **232 characters**, within Product Hunt's current 60/260 limits.

## Application checks

- GitHub's latest published release was confirmed as **v1.5.2**, with DMG, ZIP, checksums and signed feed assets present. This preparation did not download a new app package or inflate its release download count.
- The existing fixture suite completed **128 tests across 18 suites: 125 passed and 3 optional FFmpeg tests skipped** because those optional tools were unavailable.
- The existing release executable's `--self-test` passed. The controlled CPU worker measured 82.2% of one core; the 256 MiB allocation measured a 258 MB footprint. Received TCP bytes, sent TCP bytes and disk writes each measured **8,388,608 bytes**, matching the controlled workload.
- Existing limitations remain: the published app is ad hoc signed and not Apple-notarized; protected Trash access can require macOS permissions; per-app audio mixing, Intel builds and every sensor/device are not verified end to end.

## External steps still pending

The Product Hunt browser session was signed out, and the owner confirmed they do not have an account. No Product Hunt account, draft listing, scheduled launch, public listing or YouTube upload was created. Independent tester recruitment/results remain pending; [the tester guide](tester-guide.md) includes the invitation and feedback template. No external messages were sent.

## Reproduce the marketing exports

From the repository root on a Mac with full Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift \
  scripts/prepare-launch-media.swift \
  artifacts/launch/product-hunt/source \
  /private/tmp/mac-pulse-launch-regenerated
```

This draws captions and frames around the supplied captures and encodes the MP4 with AVFoundation. It does not capture the desktop or operate the app. New native captures must be made through the supported UI capture tools. The script also writes sampled `video-check-*` PNGs for inspection; these are verification frames, not recommended gallery uploads.
