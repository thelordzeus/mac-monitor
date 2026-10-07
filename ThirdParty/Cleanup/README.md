# Cleanup component

Mac Pulse builds its storage, cleanup and app recovery engines as the internal
`CleanupCore` module. `MacMonitorCleanup.swift` supplies the native workspace.
Required third-party copyright and MIT license notices are preserved in
[ThirdPartyNotices.txt](../../Resources/ThirdPartyNotices.txt) and included in the
app bundle as `Contents/Resources/ThirdPartyNotices.txt`.

Integration details:

- Mac Pulse colors, typography, rounded cards and tab navigation use `PulseUI`
  and the shared `Pulse` components.
- The Cleanup root hosts the shared dropdown overlay. Inventory app actions use
  a native macOS menu with the ellipsis appearance and review flow.
- Inventory supports cache selection and owner icons. Manual bulk cache removal
  uses Trash and rechecks location, ownership, activity and the reviewed tree
  fingerprint; automatic cleanup's age rules remain unchanged.
- The host collector supplies RAM, disk, CPU and pressure. The embedded monitor
  has no competing timer, collection or persistence.
- Process monitoring starts when a relevant tool is opened. Notification defaults
  are off. Scans start when a review/tool is opened.
- Saved state stays under `~/Library/Application Support/MacMonitor/Cleanup`.
  The existing storage location and bundle identifier preserve user state and
  app protection across updates.
- Deletion, identity, activity, worktree and confirmation checks remain in place.

Fixture tests in `Tests/CleanupCoreTests` cover the engines and host bridge.
Deletions use temporary fixtures; Docker, simulator and recovery tests use
injected drivers or fake commands.

When updating these engines, retain the third-party notices, run fixture/host
checks and inspect the Cleanup views. The component excludes a separate app
shell, updater, login controller and migration of other apps' saved state.
