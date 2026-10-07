# Cleanup integration verification

BlitzClean source revision: `3506723c63d7a67287636cf15dfd0f720451df98`.
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

The suite discovers 102 tests across 14 suites. With ffmpeg/ffprobe absent, three
real-media export tests are explicitly skipped; the remaining 99 checks pass.
Install those optional tools to exercise the media-export checks as well.

Destructive fixture tests act on their own temporary files or mocked drivers.
No real user cleanup, app force quit, Docker prune or simulator deletion was
performed during verification. Read-only native UI checks cover the landing
page, cache review, folder browser, file review, inventory, recovery, AI/app
controls, project controls and setup.

Mac Monitor's existing `--self-test` verifies CPU/RAM/network/disk collection and
history behavior. The release app and clean package staging bundles are checked
with strict code-signature verification, and the DMG is verified by hdiutil.
Dashboard PNG exports were rendered from real readings and visually checked for
the monitoring tab bar and complete Cleanup landing-page content.

Permission restrictions and changing processes/volumes remain practical limits.
FFmpeg export was not verified end to end on this Mac; neither were destructive
operations against the user's installed apps or development environments.
