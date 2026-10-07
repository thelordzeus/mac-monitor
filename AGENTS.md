# Delivery workflow

The user has authorized pushing completed changes and publishing updated app
downloads as the standing workflow for this repository.

- After making a requested change, run the appropriate checks, commit the task's
  changes and push them to GitHub. Preserve unrelated user changes.
- For app changes, increment the app version/build, update release notes and
  relevant documentation, and refresh screenshots when the visible UI changes.
- Build with `./scripts/build.sh`, package with
  `./scripts/package.sh --skip-build`, and verify signatures and checksums.
- Push the code, then publish a new GitHub release containing the DMG, ZIP and
  `SHA256SUMS`. Keep existing releases and their downloads intact.
- Verify the remote commit, release tag and uploaded assets before reporting
  completion. The README download links must continue pointing to the latest
  published release.
- Documentation-only changes require a commit and push; they do not require a
  new app build or download release.
- Preserve required third-party copyright and license notices.
