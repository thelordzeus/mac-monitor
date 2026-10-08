# Mac Pulse 1.5.1 navigation verification

Checked on 9 October 2026 using the release build and live Mac readings.

- `./scripts/build.sh` compiled and verified the signed app bundle.
- Dashboard images were rendered at 1080 points, the app's minimum window width, and 2100 points. All 14 selected-tab variants were rendered at both widths.
- At 1080 points, the navigation uses icon tabs and retains the active tab's full name. Overview and the longer Storage growth label fit without clipping or horizontal scrolling.
- At 2100 points, the navigation uses full labels for all tabs.
- Native Settings confirmed the running build was 1.5.1. Selecting Storage growth opened its view, and accessibility exposed all 14 tab buttons with their names and hover help.
- The tab row derives from the existing visible-tab order, so ordering and hidden-tab preferences still apply. An additional selected-tab menu is available if neither row fits. The All tabs menu remains available in the live app.

The monitoring gallery was refreshed from real readings at the minimum window width. Earlier feature screenshots remain examples of the 1.5.0 workflows. No metrics, cleanup behavior or permissions changed in this layout release.
