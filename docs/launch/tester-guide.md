# Mac Pulse: independent tester guide

Target: 5–10 people using their own Apple Silicon Macs, including at least one MacBook and one desktop where possible. Independent feedback is **pending**. The project's previous automated/native checks are not a substitute for these people trying installation.

## Recruitment message

Hi! I'm preparing to share Mac Pulse, a free native macOS app for system monitoring and storage/cache review. Would you be willing to try it for 10–15 minutes and tell me where the installation or interface is confusing?

It supports Apple Silicon and macOS 14.2+. The current build is not Apple-notarized; the README explains first launch. You don't need to delete files, grant extra permissions or share private data for this test.

Download and instructions: https://github.com/thelordzeus/mac-monitor

I'm looking for candid feedback, not a positive review. Your Mac model, macOS version, what worked and what didn't would help.

## Tasks

1. **Install:** download the DMG from the official release link, drag the app to Applications and follow the README. Record the exact point where you hesitated or saw an error. If you don't want to approve the non-notarized app, stop and report that as feedback. Don't disable system security controls.
2. **Read the dashboard:** let it collect readings for a minute. Find CPU use, memory pressure and available disk space. Is their meaning clear? Dashes mean unavailable readings; desktops correctly have no internal battery.
3. **Find an app:** use CPU or Memory, search for a known running app and inspect its history. Optionally compare with Activity Monitor at similar times. Different sampling times, per-core settings, physical footprint and shared memory can make values differ; report a concrete example rather than assuming every difference is a bug.
4. **Menu bar:** open the compact panel and click outside it. Does it dismiss? Close the main window and confirm monitoring remains available; use Quit to exit completely.
5. **Cache review only:** open Cleanup → Inventory, inspect app names/icons, select two caches and check the selected count/size. Clear the selection. Do not remove personal caches or click a final removal confirmation for this test. If something is denied or partially scanned, report the message; no extra permission is required.
6. **Projects:** if you already have a disposable development server, check whether the project/runtime/port appears. Do not stop an existing database, work service or unfamiliar process. A tester without development servers can skip this task.
7. **Updates:** open Settings → Updates and use Check for Updates. Record whether the dialog is understandable. No new release is required for this check.

An optional removal/restore test should use only a clearly disposable file you created specifically for testing. Restore can require macOS access to protected Trash locations. Denied access should leave the file untouched and show an explanation. Do not grant Full Disk Access just to complete the feedback checklist.

## Feedback template

```text
Mac model/chip:
macOS version:
Mac Pulse version:
Installed successfully? If not, where did it fail?
Did the dashboard explain CPU, memory pressure and disk space clearly?
Did app rankings/history make sense?
Did the menu-bar panel dismiss when clicking outside?
Did cache selection/count/size work? No deletion needed.
Any incorrect or missing reading? Include the comparison method/time.
One feature you would use regularly:
One thing you would change:
Would you keep using it? Why or why not?
```

Use [GitHub Issues](https://github.com/thelordzeus/mac-monitor/issues) for feedback you are comfortable making public. Crop/redact personal filenames, project names, usernames, command arguments and conversations before sharing screenshots. Never include credentials, private app data or full diagnostic dumps in a public issue.

## Owner's review

Keep a private record of tester consent and responses. Don't publish personal contact details. Summarize confirmed findings and block launch on reproducible data loss, misleading cleanup confirmation, persistent incorrect readings or installation failures you cannot explain. Mark skipped/denied checks as such; don't turn them into passes. No external messages have been sent as part of preparing this guide.
