# Mac Pulse: Product Hunt launch pack

Prepared on 31 October 2026 for the published **1.5.2 (build 12)** release.

## Listing fields

| Field | Ready-to-use value |
| --- | --- |
| Name | Mac Pulse |
| Tagline | Monitor your Mac and reclaim storage in one native app |
| Product URL | https://github.com/thelordzeus/mac-monitor |
| Download URL | https://github.com/thelordzeus/mac-monitor/releases/latest/download/Mac-Pulse-arm64.dmg |
| Pricing | Free ($0); no subscription |
| Launch tags | Menu Bar Apps, Productivity, Developer Tools |
| Maker | [Arnav Shukla, @arnav_shukla3](https://www.producthunt.com/@arnav_shukla3) |
| Availability | Available now, Apple Silicon, macOS 14.2 or newer |

The tagline is **54/60 characters**. Use this **232/260-character** description:

> Mac Pulse combines live CPU, memory, GPU, disk and network readings with storage browsing, cache review and development project controls. A free native macOS app with local history, menu-bar readouts and no account or app telemetry.

The GitHub README is the current public product page: it includes screenshots, source, requirements and installation instructions. The separate download-count dashboard is an analytics tool, not the product submission URL.

## First maker comment

Hi Product Hunt, I'm Arnav, the maker of Mac Pulse.

I wanted one place to see what my Mac's apps are using and review what's taking up storage. Mac Pulse brings system monitoring and cleanup tools together in a native macOS interface.

You can inspect CPU, memory, GPU, disk and network readings, look at app rankings and local history, keep metrics in the menu bar, and review caches with their app icons before selecting what to remove. There are also development project views for runtimes, ports and process controls.

It's free, with no account or app telemetry. Monitoring history and cleanup state stay on your Mac. Update checks and downloads contact GitHub. The project was built with AI assistance; source and verification notes are available in the repository.

A few practical details: the download supports Apple Silicon and macOS 14.2+. It is ad hoc signed and not Apple-notarized, so please read the first-launch instructions. Hardware readings depend on what macOS exposes. Inventory selections use Trash; some reviewed generated-file cleanup is permanent. Moving files to Trash doesn't immediately reclaim disk space.

I'd love feedback on two things: does combining monitoring and cleanup help your workflow, and which readings or review steps need a clearer explanation? If you try it, please include your Mac model and macOS version when reporting an issue.

Source, screenshots and downloads: https://github.com/thelordzeus/mac-monitor

## Gallery and video

Use these files from [`artifacts/launch/product-hunt`](../../artifacts/launch/product-hunt):

| Order | Asset | Purpose |
| --- | --- | --- |
| Thumbnail | `thumbnail-240.png` | Existing app icon, 240×240 PNG |
| 1 | `01-monitoring.png` | Overview detail with real system readings |
| 2 | `02-cache-review.png` | App cache icons, two selections, count/size and reviewed action |
| 3 | `03-projects.png` | Real PostgreSQL process, port and observed inactivity |
| Optional 4 | `04-app-usage.png` | Per-app CPU rankings and recent history |
| Optional 5 | `05-download.png` | Download destination and compatibility |
| Video | `mac-pulse-demo-40s.mp4` | 40-second captioned walkthrough, H.264, 1280×720, no audio |
| Captions | `mac-pulse-demo-40s.srt` | Optional YouTube captions |

Gallery images are **1270×760**. The video is assembled from actual application captures with captions and transitions, not a continuous screen recording. Values and selections were not fabricated. No files were removed, no server was stopped, and the 2.9 GB selected size is not a measured space gain. The original captures are in `source/`; the monitoring and project images deliberately show cropped feature details.

Product Hunt's live video field accepts a **YouTube or Loom link**, not an uploaded MP4 (checked 2 November 2026). If using YouTube, upload the video as public or unlisted (not private), then paste the full URL into the draft. No video upload has been performed.

Suggested YouTube title:

> Mac Pulse: native Mac monitoring and cleanup in 40 seconds

Suggested YouTube description:

> A quick look at Mac Pulse 1.5.2: system readings, app rankings, cache selection and development project monitoring. This captioned walkthrough uses real app captures. No files were removed or servers stopped. Free download, source and installation instructions: https://github.com/thelordzeus/mac-monitor. Apple Silicon, macOS 14.2+. Ad hoc signed; not Apple-notarized.

## Before scheduling

Google sign-in and personal onboarding are complete under **@arnav_shukla3**. On 2 November 2026, the submission was saved and verified in [My products & launches](https://www.producthunt.com/my/products?filter=drafts) as **In Progress (1)**, with **Scheduled (0)** and **Posted (0)**. Product Hunt distinguishes this saved in-progress submission from a finalized unscheduled draft.

The name, tagline, description, GitHub product link, free pricing, three tags, maker role and first maker comment are saved. The logo is still missing; the gallery contains one automatically imported GitHub preview. File selection did not open in the in-app browser, and Product Hunt explicitly reported that URL uploads were unavailable there. Continue editing in a regular browser to add `thumbnail-240.png` and replace the preview with the prepared gallery images. These uploads are not claimed complete. Keep the submission unscheduled until independent feedback is complete and a launch day has been chosen.

- [x] Copy, thumbnail, gallery images and captioned MP4 prepared.
- [x] Published release and download metadata checked against 1.5.2.
- [x] Compatibility, first-launch friction, unavailable sensors and cleanup limits disclosed.
- [x] Create your personal Product Hunt account and add yourself as maker.
- [x] Save the listing copy, free pricing, launch tags and first maker comment.
- [ ] Upload the logo and prepared gallery images; the in-app browser upload controls are unavailable.
- [ ] Upload the MP4 to your YouTube account if using the video field.
- [ ] Collect feedback from 5–10 independent testers using [the tester guide](tester-guide.md).
- [ ] Resolve any critical installation, incorrect-reading or removal-review issue found by testers.
- [x] Save an in-progress Product Hunt submission under your personal account.
- [ ] Complete the media fields and review the finalized draft.
- [ ] Choose a date when you can answer questions, then schedule the launch.

No launch date has been selected, no Product Hunt listing has been published and no independent tester results have been claimed.

## Launch-day message

> I just shared Mac Pulse on Product Hunt. It's a free native Mac app that combines live system monitoring with storage and cache review. If that sounds useful, I'd appreciate you trying it and sharing feedback, especially on installation and the cleanup workflow. [Insert your actual Product Hunt launch URL after publication.]

Invite feedback without requesting upvotes or buying traffic. Reply honestly about hardware support, the non-notarized build and any feature that has not been tested on the visitor's Mac.

## Measurement

Record the existing GitHub DMG and ZIP download totals immediately before launch, after 24 hours and after seven days. The [hosted dashboard](https://mac-pulse-downloads.azurepony128.chatgpt.site) reads these counters. Differences are **downloads, not unique users, installs or retention**; repeat/test downloads and updater ZIP downloads count. Without separate attribution, a counter increase cannot be assigned entirely to Product Hunt. Track substantive feedback and resolved issues alongside the counts.

## Verification and maintenance

See [the capture and asset record](media-verification.md). Marketing-only files do not change the app binary or require a new DMG release.

Official guidance checked on 31 October 2026:

- [Posting fields, 240×240 thumbnail, 1270×760 gallery and YouTube support](https://help.producthunt.com/en/articles/479557-how-to-post-a-product).
- [Launch preparation, 60-character tagline, 260-character description and launch-day engagement](https://help.producthunt.com/en/articles/17350772-launch-guide).

Recheck the live submission form before scheduling; platform fields can change.
