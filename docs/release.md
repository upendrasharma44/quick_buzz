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
3. **Screenshots** (when UI changed): `scripts/screenshots.sh` → `docs/app-store/screenshots/`.
   Check them, commit.
4. **Device test.** Run the stage scripts in `docs/testing.md` on ≥ 3 real iPhones; record the
   results in the stage issue.
5. 👤 **Archive & upload.** Xcode → select *Any iOS Device (arm64)* → Product → Archive →
   Organizer → Distribute App → App Store Connect → Upload.
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
| 1.0.0 | 1 | — | Stage 3: first App Store release (pending) |
