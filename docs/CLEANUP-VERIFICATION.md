# Cleanup integration verification

Cleanup engines are built as the internal `CleanupCore` module.
Validation date: 7 October 2026, Apple Silicon/macOS, Xcode toolchain.

Run the fixture suite with `./scripts/test-cleanup.sh`. It exercises:

- Host collector bridging, unknown readings, RAM usage and data isolation.
- Old-report/cache eligibility, symlink escapes, age/activity and open-file checks.
- Dependencies with lockfiles, active-project blockers, source preservation,
  changed-directory identity, Git worktree merge/lock/protection rules.
- Scan budgets, hard links, incomplete measurements and concurrent scan reuse.
- Docker/simulator cleanup through fake commands or injected drivers.
- App recovery and force-quit reporting through injected drivers.
- Exact duplicates, review persistence and corrupt-history preservation.
- Inventory cache owner matching, exact bulk selections, cancellation and partial
  failures; manual Trash cleanup, path boundaries, links, changed caches and
  fresh running-app/open-file checks.

The suite discovers 112 tests across 15 suites. With ffmpeg/ffprobe absent, three
real-media export tests are explicitly skipped; the remaining 109 checks pass.
Install those optional tools to exercise the media-export checks as well.

Destructive fixture tests act on their own temporary files or mocked drivers.
No real user cleanup, app force quit, Docker prune or simulator deletion was
performed during verification. Read-only native UI checks cover the landing
page, cache review, folder browser, file review, inventory, recovery, AI/app
controls, project controls and setup.

Mac Pulse's existing `--self-test` verifies CPU/RAM/network/disk collection and
history behavior. The release app and clean package staging bundles are checked
with strict code-signature verification, and the DMG is verified by hdiutil.
Dashboard PNG exports were rendered from real readings and visually checked for
the monitoring tab bar and complete Cleanup landing-page content.

For the 1.2.1 menu regression, native UI checks confirmed that Inventory's
ellipsis opens the app action menu, Escape and an outside click dismiss it,
and activating the action closes the menu and opens the removal review.
Cancel preserved the installed app. The shared Files & media dropdown also
opened and dismissed correctly. No removal or media operation was executed.

For 1.3.0, native Inventory checks confirmed per-cache checkboxes, installed app
icons, the selected count/size footer, and Select All limited to the current
search. Preparing two real cache rows kept the running app's cache and presented
the closed app's exact cache path and measured size for confirmation. Cancel
preserved both caches. The new fixture tests cover actual moves into a temporary
fixture Trash; no real user cache was moved during native verification.

For 1.3.1, the full fixture suite passed after the module/component rename.
Native checks confirmed the Cleanup landing page, Setup, Inventory search and
cache selection controls. The current source and resource names contain no
former branding except the required copyright notice in `ThirdPartyNotices.txt`.
The executable's strings contain no former branding, and fresh bundle resources
contain only the app icon and the neutral notices file.

Permission restrictions and changing processes/volumes remain practical limits.
FFmpeg export was not verified end to end on this Mac; neither were destructive
operations against the user's installed apps or development environments.
