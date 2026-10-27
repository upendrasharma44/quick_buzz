# Release checklist

How a BuzzLight version goes from `main` to the App Store. Steps marked 👤 need the account
holder (App Store Connect / Xcode signed in as the developer); everything else can be scripted.

## Before the first release (once)

- [ ] 👤 developer.apple.com: the App ID `com.upendrasharma.buzzlight` exists. Xcode creates it
      automatically the first time you run on a device with automatic signing
      (`Config/Local.xcconfig` → `DEVELOPMENT_TEAM`).
- [ ] 👤 App Store Connect → Apps → **+** → New App: iOS, name and SKU from
      `docs/app-store/metadata.md`, bundle ID above.
- [ ] 👤 Privacy policy URL is public. Either link the GitHub file (see `metadata.md`) or enable
      GitHub Pages (repo Settings → Pages → `main` / `docs`) and use that URL.
- [ ] 👤 Fill in App Information, Pricing (Free) and App Privacy ("Data Not Collected") from `metadata.md`.

## Every release

1. **Version.** In `project.yml` set `MARKETING_VERSION` (e.g. `1.0.0`) and increase
   `CURRENT_PROJECT_VERSION` (every upload needs a new build number). `xcodegen generate`.
2. **Green build.** CI green on `main`; locally:
   `swift test --package-path Packages/BuzzCore`, `swift test --package-path Packages/BuzzNetwork`,
   `xcodebuild test -project BuzzLight.xcodeproj -scheme BuzzLight -destination 'platform=iOS Simulator,name=iPhone 17'`.
3. **Screenshots** (when UI changed): `scripts/screenshots.sh` (iPhone 17, the required
   1206 × 2622 slot) and `scripts/screenshots.sh "iPhone 17 Pro Max"` (optional 1320 × 2868 slot)
   → `docs/app-store/screenshots/<device>/`; which folder goes in which App Store Connect slot is in
   `docs/app-store/metadata.md` → Screenshots.
   Check them, commit.
4. **Device test.** Run the stage scripts in `docs/testing.md` on ≥ 3 real iPhones; record the
   results in the stage issue.
5. **Archive & upload.** From the repo root, with Xcode signed in to the developer account
   (Claude can run this on request; it sends the build to App Store Connect, so confirm first):

   ```sh
   xcodegen generate
   ARCHIVE=$(mktemp -d)/BuzzLight.xcarchive
   xcodebuild -project BuzzLight.xcodeproj -scheme BuzzLight -configuration Release \
     -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates archive
   env PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -exportArchive -archivePath "$ARCHIVE" \
     -exportOptionsPlist Config/ExportOptions.plist -exportPath "$(mktemp -d)" -allowProvisioningUpdates
   ```

   `Config/ExportOptions.plist` signs for App Store Connect and uploads directly; the team comes
   from `Config/Local.xcconfig`. The `PATH` override matters: a Homebrew `rsync` (3.x) earlier on
   `PATH` makes the export fail with "exportArchive Copy failed" (`rsync error: syntax or usage
   error` in the `.xcdistributionlogs`). It ends with `Upload succeeded`; processing then takes up
   to an hour. GUI alternative: Xcode → *Any iOS Device (arm64)* → Product → Archive → Organizer →
   Distribute App → App Store Connect → Upload.
   👤 Then App Store Connect → the version → **Build** → **+** → pick the build → Save. The app
   icon on the product page preview comes from this build; until one is attached it shows a grid
   placeholder.
6. 👤 **TestFlight.** Add the build to an internal group (≥ 3 testers), answer export compliance
   (exempt; see `metadata.md`). Fix anything they find, back to step 1.
7. 👤 **Submit.** App Store Connect → the version → select the build, paste screenshots, text and
   `docs/app-store/review-notes.md` → Add for Review → Submit.
8. **Tag** once approved: `git tag -a v1.0.0 -m "BuzzLight 1.0.0" && git push origin v1.0.0`
   (Claude can do this on request), and add the App Store link to `README.md`.
9. **Roadmap.** Mark the stage done in `docs/roadmap.md`, close the stage issue and milestone.

## Release history

| Version | Build | Date | Notes |
|---|---|---|---|
| 1.0.0 | 1 | 2026-10-27 uploaded | Stage 3: first App Store release (uploaded via `xcodebuild -exportArchive`; review pending) |
