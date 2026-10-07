# BlitzClean component

Vendored from https://github.com/blitzreels/blitzclean at commit
`3506723c63d7a67287636cf15dfd0f720451df98` (7 October 2026).

The original copyright and MIT license are preserved in [LICENSE](LICENSE).
The app bundle contains `Contents/Resources/BlitzClean-LICENSE.txt`.

Mac Monitor builds this code as an internal `BlitzCleanIntegration` module.
`MacMonitorCleanup.swift` is the facade and native Cleanup workspace. The upstream
application entry point, dashboard, tray, updater, login controller and brand
migration are excluded. Sparkle is not a dependency.

Local adaptations:

- Mac Monitor colors, typography, rounded cards and tab navigation.
- The host collector supplies RAM, disk, CPU and pressure. The embedded monitor
  has no competing timer, collection or persistence.
- Process monitoring starts when a relevant tool is opened. Notification defaults
  are off. Scans start when a review/tool is opened.
- The host bundle identifier protects the app. Saved state is isolated under
  `~/Library/Application Support/MacMonitor/Cleanup`; no BlitzClean/FreeSpace
  files are migrated.
- Original deletion, identity, activity, worktree and confirmation checks remain.

Fixture tests in `Tests/BlitzCleanIntegrationTests` come from this revision, with
host bridge tests added. Deletions use temporary fixtures; Docker, simulator and
recovery tests use injected drivers or fake commands.

To update: review upstream, reapply these adaptations, retain the license, run
fixture/host checks and inspect Cleanup views. Do not overwrite the facade or
copy the upstream application/updater shell.
